package com.cash.dash

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Fills in the figures and the spend bar on an `item_category` row.
 *
 * Shared because the Allocator exists twice — [AllocatorFragment] behind the bottom-nav tab
 * and [AllocatorActivity] reached from History — as near-identical copies that had already
 * drifted. Changing only one would have made the same feature look like two screens.
 *
 * Reads the same two stores the Scanner's allocation chooser reads, so a limit shown here and
 * the limit shown at the moment of payment cannot disagree:
 *   - `CategoryPrefs` / `LIMIT_<name>`  — the ceiling, an Int
 *   - `GraphData` / `SPENT_<name>`      — spend so far, a Float
 */
object AllocationRowBinder {

    fun bind(context: Context, row: View, categoryName: String) {
        val figures = row.findViewById<TextView>(R.id.categoryLimit) ?: return
        val track = row.findViewById<FrameLayout>(R.id.categoryProgressTrack)
        val fill = row.findViewById<View>(R.id.categoryProgressFill)
        val limitButton = row.findViewById<TextView>(R.id.btnLimit)

        val limit = context.getSharedPreferences("CategoryPrefs", Context.MODE_PRIVATE)
            .getInt("LIMIT_$categoryName", 0)
        val spent = context.getSharedPreferences("GraphData", Context.MODE_PRIVATE)
            .getFloat("SPENT_$categoryName", 0f)
            .coerceAtLeast(0f)
            .toInt()

        // The button is laid out as "Set Limit" and used to keep saying so next to a row
        // already reading "₹371 of ₹650", which made the screen look unaware of its own
        // state. It offers to set a limit only when there isn't one.
        limitButton?.text = context.getString(
            if (limit > 0) R.string.allocator_edit_limit else R.string.allocator_set_limit
        )

        if (limit <= 0) {
            figures.text = context.getString(R.string.allocator_no_limit)
            figures.visibility = View.VISIBLE
            track?.visibility = View.GONE
            return
        }

        // "₹350 of 650" plus the remainder, because the remainder is the number people
        // actually want and the one they would otherwise work out in their head. Once the
        // limit is passed it flips to how far over, which is the same question inverted.
        val remaining = limit - spent
        figures.text = if (remaining >= 0) {
            context.getString(R.string.allocator_spent_with_left, spent, limit, remaining)
        } else {
            context.getString(R.string.allocator_spent_with_over, spent, limit, -remaining)
        }
        figures.visibility = View.VISIBLE
        track?.visibility = View.VISIBLE

        // Revealed with scaleX from a pivot of zero, so growing the bar costs a matrix rather
        // than a layout pass. Clamped at full: an overspent allocation stops at the end of its
        // track rather than drawing past it.
        fill?.apply {
            pivotX = 0f
            scaleX = (spent.toFloat() / limit).coerceIn(0f, 1f)
            setBackgroundResource(
                if (spent >= limit) R.drawable.bg_allocator_fill_over
                else R.drawable.bg_allocator_fill
            )
        }
    }
}
