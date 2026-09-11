package com.cash.dash

import android.graphics.Rect
import android.view.TouchDelegate
import android.view.View

/**
 * Grows a view's tappable area without changing a pixel of how it looks.
 *
 * ### Why this exists rather than just making the view bigger
 *
 * The accessibility guideline asks for a 48dp touch target, and the obvious fix — set the
 * view to 48dp and push the icon back down with padding — is the right one *most* of the
 * time. It is the wrong one when the icon is deliberately small and sits inline with text.
 *
 * The wallet balance edit pencil is the case that proved it. It is a 15dp glyph beside a
 * 16sp line of text. Reboxing it at 48dp with padding rendered the glyph at 22dp, noticeably
 * larger than the text it annotates, and the 8dp margin then sat outside 13dp of internal
 * padding, so the gap to the text roughly tripled. The control was more tappable and visibly
 * wrong.
 *
 * A TouchDelegate separates the two concerns: the view keeps its 15dp bounds and its margin,
 * and the *parent* is told to route touches from a larger rectangle to it.
 *
 * ### Constraints worth knowing before using this
 *
 * - The expanded rectangle is clipped to the parent's bounds. If a view sits flush against
 *   the edge of a small parent, the extra area on that side has nowhere to go.
 * - A parent holds ONE TouchDelegate, so two expanded siblings in the same parent will
 *   fight: the second call replaces the first. Use [TouchDelegateComposite] if that comes up.
 * - The view must already be laid out, which is why the work is posted rather than run
 *   immediately.
 */
fun View.expandTouchTargetTo(minimumDp: Int = 48) {
    val parentView = parent as? View ?: return
    parentView.post {
        val minimumPx = (minimumDp * resources.displayMetrics.density).toInt()
        val bounds = Rect()
        getHitRect(bounds)

        val growX = ((minimumPx - bounds.width()) / 2).coerceAtLeast(0)
        val growY = ((minimumPx - bounds.height()) / 2).coerceAtLeast(0)
        if (growX == 0 && growY == 0) return@post

        bounds.inset(-growX, -growY)
        parentView.touchDelegate = TouchDelegate(bounds, this)
    }
}
