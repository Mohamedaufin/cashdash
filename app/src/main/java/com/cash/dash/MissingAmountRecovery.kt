package com.cash.dash

import android.graphics.Bitmap
import android.graphics.Color

/** Recovery path for receipts whose headline amount disappears in full-image OCR. */
internal object MissingAmountRecovery {
    /**
     * Payment apps consistently place the headline transaction summary above their
     * details list. Cropping that region makes a small `₹1` materially larger to ML Kit
     * without admitting transaction IDs from the lower half of the screenshot.
     */
    fun createHeaderScan(source: Bitmap): Bitmap? {
        val top = source.height / 14
        val bottom = source.height * 11 / 20
        if (bottom <= top || source.width <= 0) return null
        val region = Bitmap.createBitmap(source, 0, top, source.width, bottom - top)
        val scale = (1800f / source.width).coerceIn(1.25f, 3f)
        val scaled = Bitmap.createScaledBitmap(
            region,
            (region.width * scale).toInt(),
            (region.height * scale).toInt(),
            true
        )
        if (scaled !== region) region.recycle()
        return scaled
    }

    /**
     * A second, much tighter scan around where payment apps place the headline figure.
     * It gives tiny values such as ₹1 about 2.5× more pixels than the general header
     * scan, which matters on dark GPay receipts where ML Kit can drop the whole line.
     */
    fun createFocusedAmountScan(source: Bitmap): Bitmap? {
        val left = source.width / 4
        val right = source.width * 3 / 4
        val top = source.height / 5
        val bottom = source.height * 21 / 50
        if (right <= left || bottom <= top) return null
        val region = Bitmap.createBitmap(source, left, top, right - left, bottom - top)
        val scaled = Bitmap.createScaledBitmap(region, 1800, (region.height * 1800f / region.width).toInt(), false)
        if (scaled !== region) region.recycle()
        return scaled
    }

    /** Makes white-on-black and black-on-white receipt text equally legible to OCR. */
    fun normalizeForOcr(source: Bitmap): Bitmap {
        val samples = listOf(
            source.getPixel(0, 0), source.getPixel(source.width - 1, 0),
            source.getPixel(0, source.height - 1), source.getPixel(source.width - 1, source.height - 1)
        ).map(::luminance).sorted()
        val background = samples[samples.size / 2]
        val darkBackground = background < 128
        val result = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        for (y in 0 until source.height) {
            for (x in 0 until source.width) {
                val ink = if (darkBackground) luminance(source.getPixel(x, y)) > background + 72
                else luminance(source.getPixel(x, y)) < background - 72
                result.setPixel(x, y, if (ink) Color.BLACK else Color.WHITE)
            }
        }
        return result
    }

    /** Accept only a currency-shaped read or a visually dominant headline number. */
    fun resolve(scan: Bitmap, lines: List<ReceiptLine>): Int? {
        val match = PaymentScreenshotParser.amountInCrop(lines) ?: return null
        val box = intArrayOf(match.left, match.top, match.width, match.height)
        LeadingRupeeDetector.correctedAmount(scan, box, match.value)?.let { return it }
        if (match.evidence.isReliable) return match.value

        // A bare number is allowed only when it is headline-sized. This rejects dates,
        // status-bar figures and account suffixes while still recovering a glyph that
        // OCR omitted entirely rather than misreading as 7.
        val minimumHeadlineHeight = maxOf(32, scan.height / 24)
        return match.value.takeIf { match.height >= minimumHeadlineHeight }
    }

    private fun luminance(color: Int): Int =
        (Color.red(color) * 299 + Color.green(color) * 587 + Color.blue(color) * 114) / 1000
}
