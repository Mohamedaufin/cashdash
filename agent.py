import os
import sys
import json
import shlex
import subprocess
import difflib
from pathlib import Path
from typing import Optional

import requests


# ============================================================
# CASHDASH CODE AGENT v3
# Claude Opus 5.5 via CodeCraft OpenAI-compatible API
#
# Features:
# - Proper OpenAI-compatible tool calling
# - Read/search/list files
# - Safe path sandbox
# - Edit/replace files with diff + approval
# - Create files with diff + approval
# - Run PowerShell commands with approval
# - Gradle build/test support
# - Git status/diff/log
# - Logcat/crash-log inspection
# - Iterative error -> fix -> build loop
# - Conversation memory
# - /auto mode
# - /undo via git checkout (approval required)
# - /compact to reduce conversation size
# - /reset conversation
# - /model
# - /help
#
# IMPORTANT:
# Keep your API key in CODECRAFT_API_KEY.
# Do not hard-code it in this file.
# ============================================================


# -----------------------------
# Configuration
# -----------------------------

API_KEY = os.environ.get("CODECRAFT_API_KEY")

if not API_KEY:
    print(
        'ERROR: CODECRAFT_API_KEY is not set.\n'
        'PowerShell example:\n'
        '$env:CODECRAFT_API_KEY="cc_YOUR_NEW_KEY"'
    )
    sys.exit(1)

BASE_URL = "https://codecraftapi.com/v1/chat/completions"
DEFAULT_MODEL = "claude-opus-5.5"

PROJECT = Path.cwd().resolve()

MAX_ITERATIONS = 50
MAX_FILE_BYTES = 500_000
MAX_TOOL_OUTPUT = 40_000
MAX_SEARCH_RESULTS = 150
MAX_FILES_IN_TREE = 2000
REQUEST_TIMEOUT = 180

# Directories that are generally useless/noisy for an agent.
IGNORED_DIRS = {
    ".git",
    ".gradle",
    ".idea",
    ".kotlin",
    "build",
    "node_modules",
    ".vscode",
    ".freebuff",
    "__pycache__",
}

# Files that may contain secrets or machine-specific information.
SENSITIVE_FILES = {
    "local.properties",
    ".env",
    ".env.local",
    ".env.production",
}

# Binary/generated extensions we don't want to read as source.
BINARY_EXTENSIONS = {
    ".apk", ".aab", ".jar", ".aar", ".class",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico",
    ".mp4", ".mov", ".avi", ".mkv",
    ".zip", ".7z", ".rar",
    ".db", ".sqlite", ".sqlite3",
    ".so", ".dll", ".exe",
    ".pdf",
}


# -----------------------------
# Runtime state
# -----------------------------

MODEL = DEFAULT_MODEL
AUTO_MODE = False
MESSAGES = []
CHANGES_THIS_SESSION = []


# ============================================================
# UI
# ============================================================

def print_banner():
    print()
    print("╔══════════════════════════════════════════════════════════╗")
    print("║                 CASHDASH CODE AGENT v3                  ║")
    print("║                 Claude Opus 5.5                          ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print()
    print(f"Project : {PROJECT}")
    print(f"Model   : {MODEL}")
    print(f"Mode    : {'AUTO' if AUTO_MODE else 'APPROVAL'}")
    print()
    print("Type /help for commands.")
    print()


def clipped(text, limit=MAX_TOOL_OUTPUT):
    text = str(text)
    if len(text) <= limit:
        return text
    return text[:limit] + "\n\n...[OUTPUT TRUNCATED]..."


def yes_no(prompt, default=False):
    if AUTO_MODE:
        return True

    suffix = "[Y/n]" if default else "[y/N]"
    answer = input(f"{prompt} {suffix}: ").strip().lower()

    if not answer:
        return default

    return answer in {"y", "yes"}


# ============================================================
# Security / paths
# ============================================================

def safe_path(relative_path: str) -> Path:
    relative_path = str(relative_path).strip().strip("\"'")

    target = (PROJECT / relative_path).resolve()

    try:
        target.relative_to(PROJECT)
    except ValueError:
        raise RuntimeError(
            f"Path is outside project: {relative_path}"
        )

    return target


def is_sensitive(path: Path) -> bool:
    try:
        rel = path.relative_to(PROJECT)
        return any(part in SENSITIVE_FILES for part in rel.parts)
    except ValueError:
        return True


def is_ignored(path: Path) -> bool:
    if path.name in SENSITIVE_FILES:
        return True

    if path.suffix.lower() in BINARY_EXTENSIONS:
        return True

    return any(part in IGNORED_DIRS for part in path.parts)


# ============================================================
# File tools
# ============================================================

def list_files(path: str = ".", max_results: int = MAX_FILES_IN_TREE):
    root = safe_path(path)

    if not root.exists():
        return f"ERROR: path does not exist: {path}"

    if not root.is_dir():
        return f"ERROR: not a directory: {path}"

    results = []

    for item in root.rglob("*"):
        if not item.is_file():
            continue

        if is_ignored(item):
            continue

        try:
            rel = item.relative_to(PROJECT)
            results.append(str(rel))
        except ValueError:
            continue

        if len(results) >= max_results:
            break

    results.sort()

    return "\n".join(results) if results else "(no source files found)"


def read_file(path: str, start_line: Optional[int] = None,
              end_line: Optional[int] = None):
    target = safe_path(path)

    if is_sensitive(target):
        return "ERROR: refusing to read sensitive file."

    if not target.exists():
        return f"ERROR: file does not exist: {path}"

    if not target.is_file():
        return f"ERROR: not a file: {path}"

    size = target.stat().st_size

    if size > MAX_FILE_BYTES:
        return (
            f"ERROR: file is {size} bytes, which exceeds the "
            f"{MAX_FILE_BYTES} byte safety limit. "
            f"Use search_code or request a specific range."
        )

    try:
        content = target.read_text(
            encoding="utf-8",
            errors="replace",
        )
    except Exception as exc:
        return f"ERROR reading {path}: {exc}"

    lines = content.splitlines()

    if start_line is None:
        start_line = 1

    if end_line is None:
        end_line = len(lines)

    start_line = max(1, int(start_line))
    end_line = min(len(lines), int(end_line))

    selected = lines[start_line - 1:end_line]

    numbered = []
    for number, line in enumerate(
        selected,
        start=start_line
    ):
        numbered.append(f"{number:5}: {line}")

    return "\n".join(numbered)


def search_code(pattern: str, path: str = ".",
                max_results: int = MAX_SEARCH_RESULTS):
    root = safe_path(path)

    if not root.exists():
        return f"ERROR: path does not exist: {path}"

    pattern_lower = pattern.lower()
    results = []

    for item in root.rglob("*"):
        if not item.is_file():
            continue

        if is_ignored(item):
            continue

        try:
            if item.stat().st_size > MAX_FILE_BYTES:
                continue

            text = item.read_text(
                encoding="utf-8",
                errors="ignore"
            )
        except Exception:
            continue

        for line_no, line in enumerate(
            text.splitlines(),
            start=1
        ):
            if pattern_lower in line.lower():
                rel = item.relative_to(PROJECT)
                results.append(
                    f"{rel}:{line_no}: {line.strip()}"
                )

                if len(results) >= max_results:
                    return "\n".join(results)

    if not results:
        return "No matches found."

    return "\n".join(results)


def file_exists(path: str):
    target = safe_path(path)
    return {
        "exists": target.exists(),
        "is_file": target.is_file() if target.exists() else False,
        "is_directory": target.is_dir() if target.exists() else False,
    }


# ============================================================
# Diff / editing
# ============================================================

def show_diff(old: str, new: str, path: str):
    if old == new:
        print(f"\nNo changes needed: {path}")
        return False

    diff = difflib.unified_diff(
        old.splitlines(),
        new.splitlines(),
        fromfile=f"{path} (old)",
        tofile=f"{path} (new)",
        lineterm=""
    )

    diff_text = "\n".join(diff)

    print()
    print("╔════════════════════ PROPOSED CHANGE ═══════════════════╗")
    print(diff_text)
    print("╚═══════════════════════════════════════════════════════╝")
    print()

    return True


def write_file(path: str, content: str):
    target = safe_path(path)

    if is_sensitive(target):
        return "ERROR: refusing to modify a sensitive file."

    if target.exists() and not target.is_file():
        return "ERROR: target is not a file."

    old = ""

    if target.exists():
        try:
            old = target.read_text(
                encoding="utf-8",
                errors="replace"
            )
        except Exception as exc:
            return f"ERROR reading existing file: {exc}"

    if not show_diff(old, content, path):
        return "No changes were made."

    if not yes_no(f"Apply changes to {path}?"):
        return "USER_REJECTED_CHANGE"

    try:
        target.parent.mkdir(
            parents=True,
            exist_ok=True
        )

        target.write_text(
            content,
            encoding="utf-8"
        )

        CHANGES_THIS_SESSION.append(path)

        return f"Successfully wrote {path}"

    except Exception as exc:
        return f"ERROR writing {path}: {exc}"


def replace_in_file(
    path: str,
    old_text: str,
    new_text: str,
    expected_replacements: int = 1
):
    target = safe_path(path)

    if is_sensitive(target):
        return "ERROR: refusing to modify a sensitive file."

    if not target.exists():
        return f"ERROR: file does not exist: {path}"

    try:
        original = target.read_text(
            encoding="utf-8",
            errors="replace"
        )
    except Exception as exc:
        return f"ERROR reading {path}: {exc}"

    count = original.count(old_text)

    if count == 0:
        return (
            "ERROR: old_text was not found in the file. "
            "Read the file again and use the exact text."
        )

    if count != expected_replacements:
        return (
            f"ERROR: old_text occurs {count} times, but "
            f"expected_replacements={expected_replacements}. "
            f"Use a more specific replacement."
        )

    updated = original.replace(
        old_text,
        new_text,
        expected_replacements
    )

    if not show_diff(original, updated, path):
        return "No changes needed."

    if not yes_no(f"Apply edit to {path}?"):
        return "USER_REJECTED_CHANGE"

    try:
        target.write_text(
            updated,
            encoding="utf-8"
        )

        CHANGES_THIS_SESSION.append(path)

        return f"Successfully edited {path}"

    except Exception as exc:
        return f"ERROR writing {path}: {exc}"


# ============================================================
# Command execution
# ============================================================

SAFE_COMMAND_PREFIXES = (
    "git ",
    ".\\gradlew",
    "gradlew",
    "gradle ",
    "java ",
    "javac ",
    "adb ",
    "npm ",
    "npx ",
    "node ",
    "python ",
    "pytest ",
    "pip ",
    "flutter ",
    "dart ",
    "powershell -command get-",
    "type ",
    "where ",
    "findstr ",
)

DANGEROUS_COMMAND_PARTS = (
    "format ",
    "diskpart",
    "shutdown",
    "restart-computer",
    "stop-computer",
    "remove-item c:\\",
    "remove-item s:\\",
    "rd /s /q c:\\",
    "rd /s /q s:\\",
    "del /s /q c:\\",
    "del /s /q s:\\",
    "git reset --hard",
    "git clean -fd",
)


def command_is_dangerous(command: str) -> bool:
    lower = command.lower().strip()

    return any(
        part in lower
        for part in DANGEROUS_COMMAND_PARTS
    )


def run_command(command: str, timeout_seconds: int = 600):
    command = command.strip()

    if not command:
        return "ERROR: empty command."

    if command_is_dangerous(command):
        return (
            "COMMAND BLOCKED because it is potentially destructive: "
            + command
        )

    print()
    print("┌─ COMMAND ─────────────────────────────────────────────")
    print(command)
    print("└───────────────────────────────────────────────────────")
    print()

    # In normal mode, require approval for arbitrary commands.
    # Common read/build/test commands can be auto-approved.
    lower = command.lower()

    automatically_safe = any(
        lower.startswith(prefix)
        for prefix in SAFE_COMMAND_PREFIXES
    )

    if not automatically_safe:
        if not yes_no("Allow this command to run?"):
            return "USER_REJECTED_COMMAND"

    try:
        result = subprocess.run(
            command,
            cwd=PROJECT,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout_seconds
        )

        stdout = result.stdout or ""
        stderr = result.stderr or ""

        output = stdout

        if stderr:
            output += "\n" + stderr

        output = clipped(output)

        print(output)

        print()
        print(f"Exit code: {result.returncode}")

        return (
            f"EXIT_CODE: {result.returncode}\n"
            f"STDOUT/STDERR:\n{output}"
        )

    except subprocess.TimeoutExpired:
        return (
            f"ERROR: command timed out after "
            f"{timeout_seconds} seconds."
        )

    except Exception as exc:
        return f"ERROR executing command: {exc}"


# ============================================================
# Git helpers
# ============================================================

def git_status():
    return run_command("git status --short")


def git_diff():
    return run_command("git diff --")


def git_log(count: int = 10):
    count = max(1, min(int(count), 50))
    return run_command(
        f"git log --oneline -n {count}"
    )


# ============================================================
# Android helpers
# ============================================================

def gradle_build():
    return run_command(
        ".\\gradlew.bat assembleDebug",
        timeout_seconds=900
    )


def gradle_test():
    return run_command(
        ".\\gradlew.bat test",
        timeout_seconds=900
    )


def gradle_lint():
    return run_command(
        ".\\gradlew.bat lint",
        timeout_seconds=900
    )


def gradle_tasks():
    return run_command(
        ".\\gradlew.bat tasks",
        timeout_seconds=300
    )


# ============================================================
# Tool definitions for Claude
# ============================================================

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_files",
            "description": (
                "List source/project files. Use this to explore "
                "the repository before making assumptions."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative directory path.",
                        "default": "."
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Maximum files to return.",
                        "default": 500
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": (
                "Read a source/config file. Use this before editing."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative file path."
                    },
                    "start_line": {
                        "type": "integer",
                        "description": "Optional 1-based start line."
                    },
                    "end_line": {
                        "type": "integer",
                        "description": "Optional inclusive end line."
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_code",
            "description": (
                "Search source files for a string/class/function/import/"
                "resource name/error text."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "pattern": {
                        "type": "string",
                        "description": "Text to search for."
                    },
                    "path": {
                        "type": "string",
                        "description": "Optional directory to search.",
                        "default": "."
                    },
                    "max_results": {
                        "type": "integer",
                        "default": 100
                    }
                },
                "required": ["pattern"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "file_exists",
            "description": "Check whether a project path exists.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": (
                "Create or replace a source file. The agent shows a "
                "diff and asks for approval unless AUTO mode is enabled."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string"
                    },
                    "content": {
                        "type": "string"
                    }
                },
                "required": ["path", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "replace_in_file",
            "description": (
                "Make a precise replacement in a file. Use after "
                "reading the file and only when the old text is exact."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string"
                    },
                    "old_text": {
                        "type": "string"
                    },
                    "new_text": {
                        "type": "string"
                    },
                    "expected_replacements": {
                        "type": "integer",
                        "default": 1
                    }
                },
                "required": [
                    "path",
                    "old_text",
                    "new_text"
                ]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": (
                "Run a terminal command inside the project. "
                "Use for builds, tests, git, adb, scripts, etc."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string"
                    },
                    "timeout_seconds": {
                        "type": "integer",
                        "default": 600
                    }
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "git_status",
            "description": "Show git working tree status.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "git_diff",
            "description": "Show current git diff.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "git_log",
            "description": "Show recent git commits.",
            "parameters": {
                "type": "object",
                "properties": {
                    "count": {
                        "type": "integer",
                        "default": 10
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "gradle_build",
            "description": "Build Android debug APK with Gradle.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "gradle_test",
            "description": "Run Gradle tests.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "gradle_lint",
            "description": "Run Android Gradle lint.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "gradle_tasks",
            "description": "List Gradle tasks.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    }
]


# ============================================================
# Tool dispatcher
# ============================================================

def dispatch_tool(name, args):

    try:
        if name == "list_files":
            return list_files(
                args.get("path", "."),
                args.get("max_results", 500)
            )

        if name == "read_file":
            return read_file(
                args["path"],
                args.get("start_line"),
                args.get("end_line")
            )

        if name == "search_code":
            return search_code(
                args["pattern"],
                args.get("path", "."),
                args.get("max_results", 100)
            )

        if name == "file_exists":
            return file_exists(args["path"])

        if name == "write_file":
            return write_file(
                args["path"],
                args["content"]
            )

        if name == "replace_in_file":
            return replace_in_file(
                args["path"],
                args["old_text"],
                args["new_text"],
                args.get("expected_replacements", 1)
            )

        if name == "run_command":
            return run_command(
                args["command"],
                args.get("timeout_seconds", 600)
            )

        if name == "git_status":
            return git_status()

        if name == "git_diff":
            return git_diff()

        if name == "git_log":
            return git_log(args.get("count", 10))

        if name == "gradle_build":
            return gradle_build()

        if name == "gradle_test":
            return gradle_test()

        if name == "gradle_lint":
            return gradle_lint()

        if name == "gradle_tasks":
            return gradle_tasks()

        return f"ERROR: unknown tool: {name}"

    except Exception as exc:
        return f"TOOL ERROR ({name}): {exc}"


# ============================================================
# Claude system prompt
# ============================================================

def build_system_prompt():

    return f"""
You are a senior autonomous coding agent operating inside this project.

PROJECT ROOT:
{PROJECT}

MODEL:
{MODEL}

You have real tools. USE THEM.

IMPORTANT:
- When the user asks about project code, actually inspect the project.
- Do not say "I'll read it" without calling a tool.
- Do not claim you inspected a file unless a tool result was returned.
- Do not invent file contents.
- Use search_code to locate unknown classes/functions.
- Use read_file to inspect relevant source.
- Use git_status/git_diff before and after substantial work.
- Use gradle_build after Android code changes when appropriate.
- If the build fails, inspect the exact compiler/error output.
- Fix the root cause, not just the first visible symptom.
- Repeat build -> inspect -> edit -> build as needed.
- Do not stop merely because you found an error.
- Preserve existing behavior unless the user asks to change it.
- Make minimal, targeted edits.
- Never read or expose secrets.
- Never modify files outside the project root.
- Do not modify local.properties.
- Never run destructive commands unless explicitly requested.
- Never use git reset --hard or git clean -fd.
- Do not commit or push unless explicitly requested.

ANDROID:
- This is an Android/Gradle project.
- Prefer gradle_build for debug build verification.
- Use gradle_test for tests.
- Use gradle_lint for lint.
- If a Gradle task fails, use its output as evidence.

CONVERSATION:
- Answer ordinary questions normally.
- For code questions, use tools first when project context is needed.
- Give a concise but complete final explanation.
- Mention files changed and verification commands.
"""


# ============================================================
# API request
# ============================================================

def call_claude(messages):

    payload = {
        "model": MODEL,
        "messages": messages,
        "tools": TOOLS,
        "tool_choice": "auto",
        "max_tokens": 16000,
        "temperature": 0.1,
    }

    try:
        response = requests.post(
            BASE_URL,
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=REQUEST_TIMEOUT
        )
    except Exception as exc:
        print(f"\nAPI connection error: {exc}")
        return None

    if not response.ok:
        print("\nAPI ERROR")
        print("Status:", response.status_code)
        print(response.text)
        return None

    try:
        return response.json()
    except Exception:
        print("Invalid JSON from API:")
        print(response.text)
        return None


# ============================================================
# Conversation
# ============================================================

def add_user_message(text):
    MESSAGES.append({
        "role": "user",
        "content": text
    })


def print_text(content):
    if not content:
        return

    print()
    print("Claude:")
    print(content)


def run_turn(user_text):

    add_user_message(user_text)

    for iteration in range(1, MAX_ITERATIONS + 1):

        print()
        print(
            f"──── agent step {iteration}/{MAX_ITERATIONS} ────"
        )

        data = call_claude(MESSAGES)

        if not data:
            return

        choice = data.get("choices", [{}])[0]
        message = choice.get("message", {})

        content = message.get("content")
        tool_calls = message.get("tool_calls") or []

        # Preserve the assistant message exactly as returned.
        assistant_message = {
            "role": "assistant",
            "content": content or ""
        }

        if tool_calls:
            assistant_message["tool_calls"] = tool_calls

        MESSAGES.append(assistant_message)

        if content:
            print_text(content)

        # No tools = Claude finished this turn.
        if not tool_calls:
            return

        # Execute every tool call in this assistant message.
        for tool_call in tool_calls:

            function = tool_call.get("function", {})
            name = function.get("name")
            raw_args = function.get("arguments", "{}")

            try:
                args = json.loads(raw_args)
            except Exception:
                args = {}

            print()
            print(
                f"🔧 {name}("
                + ", ".join(
                    f"{k}={repr(v)[:120]}"
                    for k, v in args.items()
                )
                + ")"
            )

            result = dispatch_tool(
                name,
                args
            )

            MESSAGES.append({
                "role": "tool",
                "tool_call_id": tool_call.get("id"),
                "name": name,
                "content": clipped(result)
            })

    print(
        "\nAgent reached the maximum number of steps."
    )


# ============================================================
# Slash commands
# ============================================================

def reset_conversation():

    global MESSAGES

    MESSAGES = [
        {
            "role": "system",
            "content": build_system_prompt()
        }
    ]

    print("Conversation reset.")


def compact_conversation():

    global MESSAGES

    if len(MESSAGES) <= 6:
        print("Conversation is already short.")
        return

    # Ask Claude for a compact summary of the current work.
    temp = MESSAGES + [{
        "role": "user",
        "content": (
            "Create a compact engineering handoff summary of the "
            "conversation so far. Include current task, important "
            "findings, files changed, errors, attempted fixes, and "
            "remaining work. Do not omit critical technical details."
        )
    }]

    data = call_claude(temp)

    if not data:
        return

    message = (
        data.get("choices", [{}])[0]
        .get("message", {})
    )

    summary = message.get("content", "")

    MESSAGES = [
        {
            "role": "system",
            "content": build_system_prompt()
        },
        {
            "role": "user",
            "content": (
                "Previous session context:\n\n"
                + summary
            )
        }
    ]

    print("Conversation compacted.")


def show_help():

    print("""
Commands:

  /help
      Show this help.

  /status
      Show git status.

  /diff
      Show git diff.

  /log
      Show recent commits.

  /files
      List project files.

  /build
      Run Android debug build.

  /test
      Run Gradle tests.

  /lint
      Run Android lint.

  /tasks
      List Gradle tasks.

  /auto
      Toggle automatic approval mode.

  /reset
      Reset the conversation.

  /compact
      Compress the conversation into an engineering summary.

  /model
      Show current model.

  /exit
      Exit the agent.

Examples:

  Summarise ScannerActivity.

  Find the crash in the scanner and fix it.

  Run the build and fix all compilation errors.

  Explain how CashDash handles UPI transactions.

  Find all Firebase usage in this project.

  Refactor ScannerActivity without changing behavior.

  Run tests and fix failures.

  Review my current uncommitted changes for bugs.
""")


def handle_command(command):

    global AUTO_MODE

    lower = command.lower().strip()

    if lower == "/help":
        show_help()
        return True

    if lower == "/status":
        print(git_status())
        return True

    if lower == "/diff":
        print(git_diff())
        return True

    if lower == "/log":
        print(git_log())
        return True

    if lower == "/files":
        print(list_files())
        return True

    if lower == "/build":
        print(gradle_build())
        return True

    if lower == "/test":
        print(gradle_test())
        return True

    if lower == "/lint":
        print(gradle_lint())
        return True

    if lower == "/tasks":
        print(gradle_tasks())
        return True

    if lower == "/auto":

        AUTO_MODE = not AUTO_MODE

        print(
            "AUTO MODE:",
            "ON" if AUTO_MODE else "OFF"
        )

        return True

    if lower == "/reset":
        reset_conversation()
        return True

    if lower == "/compact":
        compact_conversation()
        return True

    if lower == "/model":
        print(MODEL)
        return True

    if lower == "/exit":
        print("Goodbye.")
        sys.exit(0)

    return False


# ============================================================
# Main
# ============================================================

def main():

    reset_conversation()

    print_banner()

    while True:

        try:
            user_input = input("\nYou: ").strip()

        except KeyboardInterrupt:
            print("\nUse /exit to quit.")
            continue

        except EOFError:
            print()
            break

        if not user_input:
            continue

        if handle_command(user_input):
            continue

        run_turn(user_input)


if __name__ == "__main__":
    main()
