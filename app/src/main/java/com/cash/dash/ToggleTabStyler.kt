package com.cash.dash

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import com.google.android.material.button.MaterialButton

/**
 * Repaints a [com.google.android.material.button.MaterialButtonToggleGroup]'s buttons in the
 * app's own colours.
 *
 * ### The problem this exists to solve
 *
 * A MaterialButton inside a toggle group lets Material own its checked state, and Material
 * paints that from `colorPrimary`. This app sets `colorPrimary` to the brand violet, so a
 * selected tab came out lavender and a tap threw a violet ripple — the only two places in an
 * otherwise monochrome app where that hue appeared, and in both cases by accident rather than
 * because the colour meant anything.
 *
 * ### Why state lists rather than flat colours
 *
 * Assigning `ColorStateList.valueOf(someColour)` per button leaves Material's own checked
 * default underneath and merely covers it, so switching tabs shows the violet for a frame
 * before the intended colour lands. A list that answers for `state_checked` replaces the
 * default outright, so there is nothing left to flash.
 *
 * The ripple has to be set separately: outlined buttons take theirs from `colorPrimary` too,
 * independently of the background tint, so fixing only the background leaves a violet splash
 * on every press. A low-alpha neutral keeps the press feedback without introducing a hue.
 *
 * Extracted from ReportActivity, which had solved this for its own tabs while the Finminder
 * screen went on showing the lavender.
 */
object ToggleTabStyler {

    fun apply(activity: Activity, vararg buttonIds: Int) {
        val activeColor = ThemeHelper.resolveColorAttr(activity, R.attr.primaryActionBackground)
        val activeTextColor = ThemeHelper.resolveColorAttr(activity, R.attr.primaryActionText)
        val inactiveTextColor = ThemeHelper.resolveColorAttr(activity, R.attr.textPrimaryColor)

        val checkedStates = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
        val bgTint = ColorStateList(checkedStates, intArrayOf(activeColor, Color.TRANSPARENT))
        val textTint = ColorStateList(checkedStates, intArrayOf(activeTextColor, inactiveTextColor))
        // The active colour at 20% alpha: visible as feedback, colourless in practice.
        val rippleTint = ColorStateList.valueOf((activeColor and 0x00FFFFFF) or 0x33000000)

        for (id in buttonIds) {
            val button = activity.findViewById<MaterialButton>(id) ?: continue
            button.backgroundTintList = bgTint
            button.setTextColor(textTint)
            button.rippleColor = rippleTint
        }
    }
}
