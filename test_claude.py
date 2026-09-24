import os
import requests

api_key = os.environ["cc_9sU2SwDtOCq7EVCf78ETjln7iVhb3r5l2PzjVrn8nAMpZcCk"]

response = requests.post(
    "https://codecraftapi.com/v1/chat/completions",
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    },
    json={
        "model": "claude-opus-5.5",
        "messages": [
            {
                "role": "user",
                "content": "Hello! Introduce yourself in one sentence."
            }
        ],
        "max_tokens": 200
    }
)

print("Status:", response.status_code)

data = response.json()

if response.ok:
    print(data["choices"][0]["message"]["content"])
else:
    print(data)