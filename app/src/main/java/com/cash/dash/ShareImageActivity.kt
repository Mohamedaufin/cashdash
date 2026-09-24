package com.cash.dash

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.view.Gravity
import android.widget.TextView
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

/** Share-sheet entry point. The image is read locally and is never uploaded or stored. */
class ShareImageActivity : ThemedActivity() {
    private data class AmountCrop(val bitmap: Bitmap, val visuallyCorrectedAmount: Int?)

    companion object {
        const val EXTRA_TITLE = "shared_payment_title"
        const val EXTRA_AMOUNT = "shared_payment_amount"
        const val EXTRA_DATE = "shared_payment_date"
        const val EXTRA_SCAN_STATUS = "shared_payment_scan_status"
        const val EXTRA_SHARED_IMAGE = "shared_payment_image"
        private const val TAG = "ShareImageActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawableResource(android.R.color.transparent)
        setContentView(TextView(this).apply {
            text = "Reading payment screenshot…"
            gravity = Gravity.CENTER
            setTextColor(ThemeHelper.resolveColorAttr(this@ShareImageActivity, R.attr.textPrimaryColor))
            setBackgroundColor(ThemeHelper.resolveColorAttr(this@ShareImageActivity, R.attr.pageTopColor))
        })
        val uri = sharedUri()
        if (uri == null) {
            openRigor(PaymentFields(false, null, null, null))
            return
        }
        val image = try { InputImage.fromFilePath(this, uri) } catch (error: Exception) {
            Log.w(TAG, "Cannot open shared image", error)
            openRigor(PaymentFields(false, null, null, null))
            return
        }
        // A screenshot from Swiggy or Myntra has no payee on it — the app is what was
        // paid. Payment apps and browsers keep the payee extraction, because there the
        // app name would be the wrong answer.
        val sourceApp = ScreenshotSource.appName(fileName(uri))
        val merchantApp = sourceApp
            ?.takeUnless { ScreenshotSource.namesAPayee(it) }
            ?.let { ScreenshotSource.displayName(it) }
        if (BuildConfig.DEBUG) Log.d(TAG, "source app=$sourceApp merchant=$merchantApp")

        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image).addOnSuccessListener { primaryText ->
            logLines("primary", primaryText.receiptLines())
            // Most phones name screenshots with only a timestamp, so when the file name
            // gave nothing, look for the brand in the text instead.
            val resolvedApp = merchantApp ?: if (sourceApp == null) {
                ScreenshotSource.appInText(primaryText.receiptLines())
                    ?.takeUnless { ScreenshotSource.namesAPayee(it) }
                    ?.let { ScreenshotSource.displayName(it) }
            } else null
            if (BuildConfig.DEBUG && resolvedApp != merchantApp) Log.d(TAG, "app from text=$resolvedApp")
            val primary = PaymentScreenshotParser.parse(primaryText.receiptLines(), image.height, resolvedApp)
            // A bare number is not good enough to skip the enhanced pass. Currency text,
            // a payment label ("Paid 7,800"), or a recognised currency glyph provides
            // enough context to trust the headline amount.
            if (primary.title != null && primary.amountEvidence?.isReliable == true && primary.date != null) {
                recognizer.close()
                openRigor(primary)
                return@addOnSuccessListener
            }
            // Pale gray text on white receipts is often missed in the normal pass.
            val enhanced = try { enhancedBitmap(uri) } catch (error: Exception) {
                Log.w(TAG, "Image enhancement unavailable", error)
                null
            }
            if (enhanced == null) {
                recognizer.close()
                openRigor(primary)
                return@addOnSuccessListener
            }
            recognizer.process(InputImage.fromBitmap(enhanced, 0))
                .addOnSuccessListener { secondaryText ->
                    val secondary = PaymentScreenshotParser.parse(secondaryText.receiptLines(), enhanced.height, resolvedApp)
                    logLines("enhanced", secondaryText.receiptLines())
                    // Prefer contextual evidence over a visually prominent bare number.
                    // This lets "Paid7,800" win while an isolated "71" still gets the
                    // crop-and-zoom recovery pass for a possibly misread ₹1.
                    val primaryReliable = primary.amountEvidence?.isReliable == true
                    val secondaryReliable = secondary.amountEvidence?.isReliable == true
                    val amount = when {
                        primaryReliable -> primary.amount
                        secondaryReliable -> secondary.amount
                        else -> primary.amount ?: secondary.amount
                    }
                    val evidence = when {
                        primaryReliable -> primary.amountEvidence
                        secondaryReliable -> secondary.amountEvidence
                        else -> primary.amountEvidence ?: secondary.amountEvidence
                    }
                    val merged = PaymentFields(
                        primary.isPayment || secondary.isPayment,
                        primary.title ?: secondary.title,
                        amount,
                        primary.date ?: secondary.date,
                        primary.amountBox ?: secondary.amountBox,
                        evidence
                    )
                    if (merged.amountEvidence?.isReliable == true) {
                        openRigor(merged)
                    } else if (merged.amountBox != null) {
                        // Neither full-image pass saw a ₹. The glyph is small relative to
                        // the whole screenshot, which is exactly when it gets dropped or
                        // read as a 7 — so re-read only that line, enlarged.
                        zoomedAmount(uri, merged.amountBox, merged.amount) { zoomed ->
                            openRigor(if (zoomed == null) merged else merged.copy(amount = zoomed, amountEvidence = AmountEvidence.CURRENCY))
                        }
                    } else {
                        // Some large display fonts disappear as a whole line — there is
                        // then no box for the normal zoom path. Re-scan the receipt header
                        // independently and accept only a currency-shaped or headline-
                        // sized number.
                        recoverMissingAmount(uri) { recovered ->
                            openRigor(if (recovered == null) merged else merged.copy(amount = recovered, amountEvidence = AmountEvidence.CURRENCY))
                        }
                    }
                }
                .addOnFailureListener { error ->
                    Log.w(TAG, "Enhanced OCR unavailable", error)
                    openRigor(primary)
                }
                .addOnCompleteListener {
                    enhanced.recycle()
                    recognizer.close()
                }
        }.addOnFailureListener { error ->
            Log.w(TAG, "OCR unavailable", error)
            recognizer.close()
            openRigor(PaymentFields(false, null, null, null))
        }
    }

    /**
     * Dumps what OCR actually read, debug builds only.
     *
     * Receipt parsing fails in ways that are invisible from the result alone — a wrong
     * amount looks the same whether the regex missed or the glyph was misread. A UPI
     * screenshot contains the payee's name and VPA, so this must never ship: the
     * BuildConfig.DEBUG check is a compile-time constant and R8 removes the calls.
     */
    private fun logLines(pass: String, lines: List<ReceiptLine>) {
        if (!BuildConfig.DEBUG) return
        Log.d(TAG, "--- OCR $pass: ${lines.size} lines ---")
        lines.sortedBy { it.top }.forEach {
            Log.d(TAG, "  top=${it.top} left=${it.left} h=${it.height} block=${it.blockId} | ${it.text}")
        }
    }

    /** File name behind the shared URI; the app that took the screenshot is in it. */
    private fun fileName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
            ?: uri.lastPathSegment
    } catch (error: Exception) {
        Log.w(TAG, "Cannot read file name", error)
        uri.lastPathSegment
    }

    private fun sharedUri(): Uri? {
        val clipUri = intent.clipData?.getItemAt(0)?.uri
        if (clipUri != null) return clipUri
        @Suppress("DEPRECATION")
        return if (Build.VERSION.SDK_INT >= 33)
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)
    }

    private fun Text.receiptLines(): List<ReceiptLine> = textBlocks.flatMapIndexed { blockId, block ->
        block.lines.mapNotNull { line ->
            line.boundingBox?.let { ReceiptLine(line.text, it.top, it.left, it.height(), it.width(), blockId) }
        }
    }

    /**
     * Re-reads just the amount line, cropped and enlarged.
     *
     * A ₹ is a handful of pixels tall in a full screenshot, so OCR drops it or reports
     * a 7 — "₹1" came back as the bare number 71. Cropping to that one line and scaling
     * it up gives the recogniser far more to work with, and the result is only used when
     * it actually produces a currency-marked amount.
     */
    private fun zoomedAmount(
        uri: Uri,
        box: IntArray,
        fullImageAmount: Int?,
        onDone: (Int?) -> Unit
    ) {
        val cropResult = try { croppedRegion(uri, box, fullImageAmount) } catch (error: Exception) {
            Log.w(TAG, "Amount crop unavailable", error)
            null
        }
        if (cropResult == null) {
            onDone(null)
            return
        }
        val crop = cropResult.bitmap
        if (BuildConfig.DEBUG && cropResult.visuallyCorrectedAmount != null) {
            Log.d(TAG, "visual ₹ correction: $fullImageAmount -> ${cropResult.visuallyCorrectedAmount}")
        }
        // Two reads of the crop: as-is, then contrast-boosted. On the Jupiter receipt
        // the plain crop agreed with the full image that "₹20" was "720", leaving
        // nothing to compare — a second rendering is another chance for one of them to
        // resolve the glyph differently.
        val contrasted = try { boostContrast(crop) } catch (error: Exception) {
            Log.w(TAG, "Crop contrast unavailable", error)
            null
        }
        val bitmaps = listOfNotNull(crop, contrasted)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        fun finish(result: Int?) {
            bitmaps.forEach { if (!it.isRecycled) it.recycle() }
            recognizer.close()
            onDone(result)
        }

        fun attempt(index: Int) {
            if (index >= bitmaps.size) {
                finish(cropResult.visuallyCorrectedAmount)
                return
            }
            val bitmap = bitmaps[index]
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { text ->
                    logLines("zoom#$index", text.receiptLines())
                    // A crop contains no status text, so it bypasses the full receipt
                    // gate and is evaluated directly as an amount line.
                    val zoomed = PaymentScreenshotParser.amountInCrop(text.receiptLines())
                    val usable = zoomed?.value
                        ?.takeIf { zoomed.evidence.isReliable || droppedRupeeGlyph(fullImageAmount, it) }
                    if (usable != null) finish(usable) else attempt(index + 1)
                }
                .addOnFailureListener { error ->
                    Log.w(TAG, "Zoomed OCR unavailable", error)
                    attempt(index + 1)
                }
        }
        attempt(0)
    }

    /**
     * True when the full image read one extra leading 7 that the zoom did not.
     *
     * The ₹ glyph is drawn much like a 7, and at full-image scale OCR regularly reports
     * it as one: "₹187" came back as 7187 while the enlarged crop of the same line read
     * 187. Neither pass sees a currency symbol, so confidence cannot settle it — but
     * one value being exactly the other with a 7 in front is the misreading itself,
     * visible. Any other disagreement is left alone, so a genuine ₹7187 is untouched.
     */
    private fun droppedRupeeGlyph(fullImageAmount: Int?, zoomedAmount: Int): Boolean {
        val full = fullImageAmount?.toString() ?: return false
        return full == "7" + zoomedAmount.toString()
    }

    /** Same contrast curve as the full-image retry, applied to the amount crop. */
    private fun boostContrast(source: Bitmap): Bitmap {
        val result = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val contrast = 2.2f
        val offset = 255f * (1f - contrast)
        val matrix = ColorMatrix(floatArrayOf(
            contrast, 0f, 0f, 0f, offset,
            0f, contrast, 0f, 0f, offset,
            0f, 0f, contrast, 0f, offset,
            0f, 0f, 0f, 1f, 0f
        ))
        Canvas(result).drawBitmap(source, 0f, 0f, Paint().apply {
            colorFilter = ColorMatrixColorFilter(matrix)
            isFilterBitmap = true
        })
        return result
    }

    private fun croppedRegion(uri: Uri, box: IntArray, ocrAmount: Int?): AmountCrop? {
        val source = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return null
        val (left, top, width, height) = listOf(box[0], box[1], box[2], box[3])
        if (width <= 0 || height <= 0) { source.recycle(); return null }
        val visuallyCorrectedAmount = LeadingRupeeDetector.correctedAmount(source, box, ocrAmount)
        // Generous horizontal padding: the ₹ sits to the left of the digits and OCR's
        // line box often starts after it, which is part of why it goes missing.
        val padX = maxOf(width / 2, height * 2)
        val padY = height / 2
        val x = (left - padX).coerceAtLeast(0)
        val y = (top - padY).coerceAtLeast(0)
        val w = (width + padX * 2).coerceAtMost(source.width - x)
        val h = (height + padY * 2).coerceAtMost(source.height - y)
        if (w <= 0 || h <= 0) { source.recycle(); return null }
        val region = Bitmap.createBitmap(source, x, y, w, h)
        source.recycle()
        val scale = (900f / maxOf(region.width, 1)).coerceIn(2f, 6f)
        val zoomed = Bitmap.createScaledBitmap(region, (region.width * scale).toInt(), (region.height * scale).toInt(), true)
        if (zoomed !== region) region.recycle()
        return AmountCrop(zoomed, visuallyCorrectedAmount)
    }

    private fun recoverMissingAmount(uri: Uri, onDone: (Int?) -> Unit) {
        val source = try {
            contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
        } catch (error: Exception) {
            Log.w(TAG, "Header amount scan unavailable", error)
            null
        }
        if (source == null) {
            onDone(null)
            return
        }
        val scans = try {
            listOfNotNull(
                MissingAmountRecovery.createFocusedAmountScan(source)?.let { "focus" to it },
                MissingAmountRecovery.createHeaderScan(source)?.let { "header" to it }
            )
        } finally { source.recycle() }
        if (scans.isEmpty()) {
            onDone(null)
            return
        }
        val variants = scans.flatMap { (name, scan) ->
            listOfNotNull(
                name to scan,
                try { "$name contrast" to boostContrast(scan) } catch (error: Exception) {
                    Log.w(TAG, "Header scan enhancement unavailable", error)
                    null
                },
                try { "$name normalized" to MissingAmountRecovery.normalizeForOcr(scan) } catch (error: Exception) {
                    Log.w(TAG, "Header scan normalization unavailable", error)
                    null
                }
            )
        }
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        fun finish(value: Int?) {
            variants.forEach { (_, bitmap) -> if (!bitmap.isRecycled) bitmap.recycle() }
            recognizer.close()
            onDone(value)
        }

        fun attempt(index: Int) {
            if (index >= variants.size) {
                finish(null)
                return
            }
            val (name, bitmap) = variants[index]
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { text ->
                    val lines = text.receiptLines()
                    logLines("amount $name", lines)
                    val recovered = MissingAmountRecovery.resolve(bitmap, lines)
                    if (recovered != null) finish(recovered) else attempt(index + 1)
                }
                .addOnFailureListener { error ->
                    Log.w(TAG, "Header amount OCR unavailable", error)
                    attempt(index + 1)
                }
        }
        attempt(0)
    }

    private fun enhancedBitmap(uri: Uri): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 3200) sample *= 2
        val source = contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val result = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        // Anchor white at white while pulling pale gray receipt lettering
        // toward black. A mid-gray pivot would wash out the date instead.
        val contrast = 2.2f
        val offset = 255f * (1f - contrast)
        val matrix = ColorMatrix(floatArrayOf(
            contrast, 0f, 0f, 0f, offset,
            0f, contrast, 0f, 0f, offset,
            0f, 0f, contrast, 0f, offset,
            0f, 0f, 0f, 1f, 0f
        ))
        Canvas(result).drawBitmap(source, 0f, 0f, Paint().apply {
            colorFilter = ColorMatrixColorFilter(matrix)
            isFilterBitmap = true
        })
        source.recycle()
        return result
    }

    private fun openRigor(fields: PaymentFields) {
        Log.i(TAG, "OCR finished: payment=${fields.isPayment}, title=${fields.title != null}, amount=${fields.amount != null}, date=${fields.date != null}")
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "parsed title=${fields.title} amount=${fields.amount} evidence=${fields.amountEvidence}")
        }
        val status = when {
            !fields.isPayment -> "Could not confirm a successful payment. Check all details before saving."
            fields.date == null -> "Payment found. Select the date from the screenshot before saving."
            else -> "Payment found. Review the details before saving."
        }
        startActivity(Intent(this, RigorActivity::class.java).apply {
            putExtra(EXTRA_SHARED_IMAGE, true)
            putExtra(EXTRA_SCAN_STATUS, status)
            fields.title?.let { putExtra(EXTRA_TITLE, it) }
            fields.amount?.let { putExtra(EXTRA_AMOUNT, it) }
            fields.date?.let { putExtra(EXTRA_DATE, it) }
        })
        overridePendingTransition(0, 0)
        finish()
        overridePendingTransition(0, 0)
    }
}
