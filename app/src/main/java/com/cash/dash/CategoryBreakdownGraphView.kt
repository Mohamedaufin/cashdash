package com.cash.dash

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View

class CategoryBreakdownGraphView(context: Context, attrs: AttributeSet?) : View(context, attrs) {

    private var categories: List<String> = emptyList()
    private var values: List<Float> = emptyList()

    private val barPaint = Paint().apply {
        color = Color.parseColor("#D9D9D9")
        isAntiAlias = true
    }

    private val textPaint = Paint().apply {
        color = Color.WHITE
        textSize = 32f
        textAlign = Paint.Align.CENTER
        isAntiAlias = true
    }

    private val barRadius = 40f

    fun setData(catList: List<String>, valueList: List<Float>) {
        categories = catList
        values = valueList
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        if (categories.isEmpty() || values.isEmpty()) return

        val count = values.size
        val maxVal = values.maxOrNull()?.takeIf { it > 0 } ?: 1f

        val barWidth = width / 14f
        val spacing = width / (count + 1f)

        val bottom = height - 140f
        val graphHeight = height - 220f

        for (i in values.indices) {

            val value = values[i]
            val center = spacing * (i + 1)

            if (value == 0f) {
                canvas.drawText("₹0", center, bottom - 25f, textPaint)
                canvas.drawText(categories[i], center, height - 70f, textPaint)
                continue
            }

            var barHeight = (value / maxVal) * graphHeight
            if (barHeight < 10f) barHeight = 10f

            val left = center - barWidth / 2
            val right = center + barWidth / 2
            val top = bottom - barHeight

            canvas.drawRoundRect(
                RectF(left, top, right, bottom),
                barRadius,
                barRadius,
                barPaint
            )

            canvas.drawText("₹${value.toInt()}", center, top - 20f, textPaint)
            canvas.drawText(categories[i], center, height - 70f, textPaint)
        }
    }
}
