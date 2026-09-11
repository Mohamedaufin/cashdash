package com.cash.dash

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Fills in the limit figures and the spend bar on an `item_category` row.
 *
 * Shared because the Allocator exists twice — [AllocatorFragment] behind the bottom-nav tab
 * and [AllocatorActivity] reached from History — as near-identical copies. Adding the bar to
 * only one would have made them visibly different screens for the same feature, and the two
 * copies had already drifted in smaller ways.
 *
 * Reads the same two stores the Scanner's allocation chooser reads, so the numbers here and
 * the numbers shown at the moment of payment cannot disagree:
 *   - `CategoryPrefs` / `LIMIT_<name>`  — the ceiling, an Int
 *   - `GraphData` / `SPENT_<name>`      — spend so far, a Float
 */
object AllocationRowBinder {

    fun bind(context: Context, row: View, categoryName: String) {
        val limitText = row.findViewById<TextView>(R.id.categoryLimit) ?: return
        val track = row.findViewById<FrameLayout>(R.id.categoryProgressTrack)
        val fill = row.findViewById<View>(R.id.categoryProgressFill)

        val limit = context.getSharedPreferences("CategoryPrefs", Context.MODE_PRIVATE)
            .getInt("LIMIT_$categoryName", 0)
        val spent = context.getSharedPreferences("GraphData", Context.MODE_PRIVATE)
            .getFloat("SPENT_$categoryName", 0f)

        if (limit <= 0) {
            // No ceiling to measure against. Showing an empty track here would read as a bar
            // that failed to load rather than as "you have not set this yet".
            limitText.text = context.getString(R.string.allocator_no_limit)
            limitText.visibility = View.VISIBLE
            track?.visibility = View.GONE
            return
        }

        limitText.text = context.getString(R.string.allocator_spent_of_limit, spent.toInt(), limit)
        limitText.visibility = View.VISIBLE
        track?.visibility = View.VISIBLE

        // Revealed with scaleX from a pivot of zero so the bar needs no layout pass, and
        // clamped at full: an overspent category stops at the end of its track rather than
        // drawing past it, exactly as the Rigor tracker does.
        val fraction = (spent / limit).coerceIn(0f, 1f)
        fill?.apply {
            pivotX = 0f
            scaleX = fraction
            setBackgroundResource(
                if (spent >= limit) R.drawable.bg_glass_progress_fill_red
                else R.drawable.bg_glass_progress_fill
            )
        }
    }
}
