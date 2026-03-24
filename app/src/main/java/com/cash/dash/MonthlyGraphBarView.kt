package com.cash.dash

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View

class MonthlyBarGraphView(context: Context, attrs: AttributeSet?) : View(context, attrs) {

    private val monthlyTotals = MutableList(12) { 0f }

    private val monthLabels = listOf(
        "Jan","Feb","Mar","Apr","May","Jun",
        "Jul","Aug","Sep","Oct","Nov","Dec"
    )

    private val barPaint = Paint().apply {
        color = Color.parseColor("#D9D9D9")
        isAntiAlias = true
    }

    private val highlightPaint = Paint().apply {
        color = Color.parseColor("#8BF7E6")
        isAntiAlias = true
    }

    private val textPaint = Paint().apply {
        color = Color.WHITE
        textSize = 28f
        textAlign = Paint.Align.CENTER
        isAntiAlias = true
    }

    private val barRadius = 40f
    private var selectedMonthIndex = 0

    // Callback for tap
    var onMonthClick: ((Int) -> Unit)? = null

    fun setMonthlyData(list: List<Float>) {
        for (i in 0 until 12) monthlyTotals[i] = list[i]
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val maxVal = monthlyTotals.maxOrNull()?.takeIf { it > 0 } ?: 1f

        val barWidth = width / 28f
        val spacing = width / 13f

        val bottom = height - 140f
        val graphHeight = height - 220f

        for (i in 0 until 12) {

            val value = monthlyTotals[i]
            val center = spacing * (i + 1)

            if (value == 0f) {
                canvas.drawText("₹0", center, bottom - 20f, textPaint)
                canvas.drawText(monthLabels[i], center, height - 70f, textPaint)
                continue
            }

            var barHeight = (value / maxVal) * graphHeight
            if (barHeight < 8f) barHeight = 8f

            val left = center - barWidth / 2
            val right = center + barWidth / 2
            val top = bottom - barHeight

            val paint = if (i == selectedMonthIndex) highlightPaint else barPaint

            canvas.drawRoundRect(
                RectF(left, top, right, bottom),
                barRadius, barRadius, paint
            )

            canvas.drawText("₹${value.toInt()}", center, top - 20f, textPaint)
            canvas.drawText(monthLabels[i], center, height - 70f, textPaint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action != MotionEvent.ACTION_DOWN) return true

        val barWidth = width / 28f
        val spacing = width / 13f

        for (i in 0 until 12) {
            val center = spacing * (i + 1)
            val left = center - barWidth / 2
            val right = center + barWidth / 2

            if (event.x in left..right) {
                selectedMonthIndex = i
                invalidate()
                onMonthClick?.invoke(i)
                return true
            }
        }
        return true
    }
}
