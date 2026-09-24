package com.cash.dash

import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Private, opt-in real-image check. Receipt images are supplied at runtime, never committed. */
@RunWith(AndroidJUnit4::class)
class PaymentScreenshotOcrTest {
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
                        ReceiptLine(line.text, it.top, it.left, it.height(), blockId)
                    } }
                }
                val parsed = PaymentScreenshotParser.parse(receiptLines, image.height)
                if (args.getString("receiptDiagnostics") == "true") {
                    instrumentation.sendStatus(0, Bundle().apply {
                        putString("stream", "\n${image.width}x${image.height}\nPARSED: title='${parsed.title}', amount=${parsed.amount}, date=${parsed.date}\n" + rows.joinToString("\n"))
                    })
                }
            bitmap.recycle()
        } finally {
            recognizer.close()
        }
    }
}
