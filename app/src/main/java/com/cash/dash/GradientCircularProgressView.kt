package com.cash.dash

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import android.view.animation.DecelerateInterpolator

class GradientCircularProgressView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private var progress = 0f
    private val strokeWidthDp = 45f
    private val ringStrokeWidth get() = strokeWidthDp * resources.displayMetrics.density

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#08123A") // Deep dark blue for track
        strokeCap = Paint.Cap.ROUND
    }

    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        setShadowLayer(15f, 0f, 0f, Color.parseColor("#80FF007A")) // Adds a subtle neon glow
    }

    private val rectF = RectF()

    init {
        // Required for shadows drawing properly in some views
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun setProgressCompat(newProgress: Int, animate: Boolean) {
        val target = newProgress.toFloat().coerceIn(0f, 100f)
        if (animate) {
            ValueAnimator.ofFloat(progress, target).apply {
                duration = 1200
                interpolator = DecelerateInterpolator(1.5f)
                addUpdateListener {
                    progress = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        } else {
            progress = target
            invalidate()
        }
    }

    private fun updateGradient(w: Float, h: Float) {
        val colors = if (progress <= 15f) {
            intArrayOf(
                Color.parseColor("#FF0033"), // Deep Red
                Color.parseColor("#FF5C00"), // Intense Orange
                Color.parseColor("#FF0033"), // Deep Red
                Color.parseColor("#FF5C00"), // Intense Orange
                Color.parseColor("#FF0033")  // Seamless loop
            )
        } else {
            intArrayOf(
                Color.parseColor("#00E5FF"), // Neon Cyan
                Color.parseColor("#4AA3FF"), // Sky Blue
                Color.parseColor("#B65CFF"), // Electric Purple
                Color.parseColor("#FF007A"), // Hot Pink
                Color.parseColor("#00E5FF")  // Seamless loop back to Cyan
            )
        }

        val sweepGradient = SweepGradient(
            w / 2f, h / 2f,
            colors,
            floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1f)
        )
        // Rotate gradient so it aligns nicely with the starting point at the top (270 degrees)
        val matrix = Matrix()
        matrix.preRotate(270f, w / 2f, h / 2f)
        sweepGradient.setLocalMatrix(matrix)
        progressPaint.shader = sweepGradient
        
        // Update shadow layer color to match
        val shadowColor = if (progress <= 15f) Color.parseColor("#80FF0033") else Color.parseColor("#80FF007A")
        progressPaint.setShadowLayer(15f, 0f, 0f, shadowColor)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val pad = ringStrokeWidth / 2f + 20f // Adding padding for the shadow
        rectF.set(pad, pad, w - pad, h - pad)
        
        trackPaint.strokeWidth = ringStrokeWidth
        progressPaint.strokeWidth = ringStrokeWidth

        updateGradient(w.toFloat(), h.toFloat())
    }

    override fun onDraw(canvas: Canvas) {
        // Ensure gradient is updated if progress crosses threshold dynamically
        if (width > 0 && height > 0) {
            updateGradient(width.toFloat(), height.toFloat())
        }
        super.onDraw(canvas)
        
        // Background track (full circle)
        canvas.drawArc(rectF, 0f, 360f, false, trackPaint)
        
        // Progress arc
        val sweepAngle = (progress / 100f) * 360f
        if (sweepAngle > 0) {
            canvas.drawArc(rectF, 270f, sweepAngle, false, progressPaint)
        }
    }
}
