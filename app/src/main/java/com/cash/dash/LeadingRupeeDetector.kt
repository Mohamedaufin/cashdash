package com.cash.dash

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import kotlin.math.abs

/**
 * Resolves the one ambiguity text OCR cannot: a leading rupee glyph read as `7`.
 *
 * The decision is made from the original pixels inside ML Kit's own line box. A rupee
 * glyph has two broad, separated horizontal bars in its upper half; Android's ordinary
 * digit 7 has only its top bar. Restricting inspection to the OCR box is important: if
 * OCR omitted the currency symbol and started its box at a genuine 7, a nearby ₹ in the
 * crop padding must not cause that real digit to be removed.
 */
internal object LeadingRupeeDetector {
    fun correctedAmount(bitmap: Bitmap, box: IntArray, ocrAmount: Int?): Int? {
        val raw = ocrAmount?.toString() ?: return null
        if (raw.length < 2 || raw.first() != '7') return null
        if (!hasLeadingRupeeShape(bitmap, box)) return null
        return raw.drop(1).toIntOrNull()?.takeIf { it > 0 }
    }

    internal fun hasLeadingRupeeShape(bitmap: Bitmap, box: IntArray): Boolean {
        if (box.size < 4) return false
        val line = Rect(
            box[0].coerceIn(0, bitmap.width),
            box[1].coerceIn(0, bitmap.height),
            (box[0] + box[2]).coerceIn(0, bitmap.width),
            (box[1] + box[3]).coerceIn(0, bitmap.height)
        )
        if (line.width() < 6 || line.height() < 8) return false

        val background = surroundingLuminance(bitmap, line)
        val threshold = 42
        val columnInk = IntArray(line.width())
        for (x in 0 until line.width()) {
            for (y in 0 until line.height()) {
                if (abs(luminance(bitmap.getPixel(line.left + x, line.top + y)) - background) >= threshold) {
                    columnInk[x]++
                }
            }
        }

        // Locate the first printed glyph, allowing one empty anti-aliasing column inside it.
        val minimumColumnInk = maxOf(1, line.height() / 12)
        val firstInk = columnInk.indexOfFirst { it >= minimumColumnInk }
        if (firstInk < 0) return false
        var end = firstInk
        var emptyRun = 0
        for (x in firstInk until columnInk.size) {
            if (columnInk[x] >= minimumColumnInk) {
                end = x
                emptyRun = 0
            } else {
                emptyRun++
                if (emptyRun >= maxOf(2, line.width() / 60)) break
            }
        }
        var start = firstInk
        // OCR sometimes clips its line box into the middle of the currency glyph: on a
        // Pop UPI receipt the box for "₹1" began 56px inside the ₹, so the analysis
        // opened on the symbol's right stroke — too narrow to be a glyph, and the
        // detector silently gave up, leaving ₹1 reported as 71. When the first inked
        // column sits on the box edge, extend left across contiguous ink to recover
        // the whole glyph. A genuine leading 7 never needs this: there is always
        // whitespace before it, so OCR's box opens on an empty column first.
        if (firstInk == 0) {
            val pad = maxOf(2, line.height() / 4)
            val floor = (line.left - pad).coerceAtLeast(0)
            var cx = line.left - 1
            while (cx >= floor) {
                var ink = 0
                for (y in 0 until line.height()) {
                    if (abs(luminance(bitmap.getPixel(cx, line.top + y)) - background) >= threshold) ink++
                }
                if (ink < minimumColumnInk) break
                cx--
            }
            start = firstInk - (line.left - 1 - cx)
        }
        val glyphWidth = end - start + 1
        if (glyphWidth < maxOf(3, line.height() / 6)) return false

        // Count substantial horizontal strokes in the upper 60% of the first glyph.
        // Requiring thickness as well as width avoids treating anti-aliasing or the
        // descending diagonal of a 7 as a second bar.
        val upperEnd = (line.height() * 3 / 5).coerceAtLeast(1)
        val wideRowMinimum = (glyphWidth * 3 + 3) / 4 // ceil(75%)
        val minimumBandHeight = maxOf(1, line.height() / 18)
        var bands = 0
        var bandHeight = 0
        for (y in 0 until upperEnd) {
            var ink = 0
            for (x in start..end) {
                if (abs(luminance(bitmap.getPixel(line.left + x, line.top + y)) - background) >= threshold) ink++
            }
            if (ink >= wideRowMinimum) {
                bandHeight++
            } else if (bandHeight > 0) {
                if (bandHeight >= minimumBandHeight) bands++
                bandHeight = 0
            }
        }
        if (bandHeight >= minimumBandHeight) bands++
        return bands >= 2
    }

    private fun surroundingLuminance(bitmap: Bitmap, line: Rect): Int {
        val pad = maxOf(2, line.height() / 4)
        val outer = Rect(
            (line.left - pad).coerceAtLeast(0),
            (line.top - pad).coerceAtLeast(0),
            (line.right + pad).coerceAtMost(bitmap.width),
            (line.bottom + pad).coerceAtMost(bitmap.height)
        )
        val samples = ArrayList<Int>((outer.width() + outer.height()) * 2)
        for (x in outer.left until outer.right) {
            for (y in outer.top until outer.bottom) {
                if (!line.contains(x, y)) samples += luminance(bitmap.getPixel(x, y))
            }
        }
        if (samples.isEmpty()) return luminance(bitmap.getPixel(line.left, line.top))
        samples.sort()
        return samples[samples.size / 2]
    }

    private fun luminance(color: Int): Int =
        (Color.red(color) * 299 + Color.green(color) * 587 + Color.blue(color) * 114) / 1000
}
