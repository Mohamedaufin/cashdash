package com.cash.dash

import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.junit.Assume.assumeTrue
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** Private, opt-in real-image check. Receipt images are supplied at runtime, never committed. */
@RunWith(AndroidJUnit4::class)
class PaymentScreenshotOcrTest {
    @Test fun visualRupeeCorrectionDoesNotStripARealSeven() {
        assertEquals(null, correctionForRenderedText("720", 720))
        assertEquals(20, correctionForRenderedText("₹20", 720))
        assertEquals(720, correctionForRenderedText("₹720", 7720))
    }

    @Test fun clippedBoxStillSeesTheRupeeGlyph() {
        // ML Kit clipped its line box 56px into the ₹ on a Pop UPI receipt: "₹1" was
        // read as 71 and the pixel detector opened on the symbol's right stroke alone —
        // too narrow to classify, so the misread survived. The detector must walk left
        // out of the box across contiguous ink, while a clipped real 7 stays untouched.
        assertEquals(1, correctionForClippedText("₹1", 71))
        assertEquals(null, correctionForClippedText("71", 71))
    }

    /**
     * Renders [text] but hands the detector a box starting well inside the first
     * glyph, the way OCR's own line box arrived clipped on the Pop receipt.
     */
    private fun correctionForClippedText(text: String, ocrAmount: Int): Int? {
        val bitmap = Bitmap.createBitmap(500, 180, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 84f
        }
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        val left = 40
        val baseline = 120
        canvas.drawText(text, left.toFloat(), baseline.toFloat(), paint)
        // Start 40px in: inside the first glyph for both "₹1" and "71".
        val clip = 40
        val box = intArrayOf(left + clip, baseline + bounds.top, bounds.width() - clip, bounds.height())
        return try {
            LeadingRupeeDetector.correctedAmount(bitmap, box, ocrAmount)
        } finally {
            bitmap.recycle()
        }
    }

    private fun correctionForRenderedText(text: String, ocrAmount: Int): Int? {
        val bitmap = Bitmap.createBitmap(500, 180, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 84f
        }
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        val left = 40
        val baseline = 120
        canvas.drawText(text, left.toFloat(), baseline.toFloat(), paint)
        val box = intArrayOf(left + bounds.left, baseline + bounds.top, bounds.width(), bounds.height())
        return try {
            LeadingRupeeDetector.correctedAmount(bitmap, box, ocrAmount)
        } finally {
            bitmap.recycle()
        }
    }

    @Test fun suppliedReceipt() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        val fixture = args.getString("receiptFixture")
        assumeTrue("Supply a receiptFixture in the app cache", fixture != null)
        val context = instrumentation.targetContext
        val file = if (fixture!!.startsWith("/")) File(fixture) else File(context.cacheDir, fixture)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: error("Cannot decode $file")
            val image = InputImage.fromBitmap(bitmap, 0)
            val text = Tasks.await(recognizer.process(image))
                val rows = text.textBlocks.flatMapIndexed { blockId, block ->
                    block.lines.mapNotNull { line -> line.boundingBox?.let {
                        "$blockId: [${it.left},${it.top},${it.width()},${it.height()}] ${line.text}"
                    } }
                }
                val receiptLines = text.textBlocks.flatMapIndexed { blockId, block ->
                    block.lines.mapNotNull { line -> line.boundingBox?.let {
                        ReceiptLine(line.text, it.top, it.left, it.height(), it.width(), blockId)
                    } }
                }
                val parsed = PaymentScreenshotParser.parse(receiptLines, image.height)
                args.getString("expectedTitle")?.replace('_', ' ')?.let { assertEquals(it, parsed.title) }
                var correctedAmount = parsed.amountBox
                    ?.let { LeadingRupeeDetector.correctedAmount(bitmap, it, parsed.amount) }
                    ?: parsed.amount
                if (correctedAmount == null) {
                    val scan = MissingAmountRecovery.createHeaderScan(bitmap)
                    if (scan != null) {
                        try {
                            val scanText = Tasks.await(recognizer.process(InputImage.fromBitmap(scan, 0)))
                            val scanLines = scanText.textBlocks.flatMapIndexed { blockId, block ->
                                block.lines.mapNotNull { line -> line.boundingBox?.let {
                                    ReceiptLine(line.text, it.top, it.left, it.height(), it.width(), blockId)
                                } }
                            }
                            correctedAmount = MissingAmountRecovery.resolve(scan, scanLines)
                            if (args.getString("receiptDiagnostics") == "true") {
                                instrumentation.sendStatus(0, Bundle().apply {
                                    putString("stream", "\nHEADER SCAN:\n" + scanLines.joinToString("\n") { "[${it.left},${it.top},${it.width},${it.height}] ${it.text}" })
                                })
                            }
                        } finally {
                            scan.recycle()
                        }
                    }
                }
                args.getString("expectedAmount")?.toIntOrNull()?.let { assertEquals(it, correctedAmount) }
                args.getString("expectedDate")?.let { expected ->
                    val actual = parsed.date?.let {
                        Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).toLocalDate().toString()
                    }
                    assertEquals(expected, actual)
                }
                if (args.getString("receiptDiagnostics") == "true") {
                    instrumentation.sendStatus(0, Bundle().apply {
                        putString("stream", "\n${image.width}x${image.height}\nPARSED: title='${parsed.title}', amount=${parsed.amount}, correctedAmount=$correctedAmount, date=${parsed.date}\n" + rows.joinToString("\n"))
                    })
                }
            bitmap.recycle()
        } finally {
            recognizer.close()
        }
    }
}
