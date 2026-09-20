@file:Suppress("DEPRECATION")
package com.cash.dash

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.MediaStore
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.ZoomSuggestionOptions
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.net.URLDecoder
import java.util.Calendar
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@androidx.annotation.OptIn(androidx.camera.core.ExperimentalGetImage::class)
class ScannerActivity : ThemedActivity(), SensorEventListener {

    private companion object {
        /** Warn once per process, not once per scan — see [warnIfDeviceCompromised]. */
        @Volatile
        var tamperWarningShown = false
    }

    private val CAMERA_REQUEST = 101
    private val GALLERY_PICK = 102
    private val PAYMENT_REQ = 500

    private lateinit var previewView: PreviewView
    private lateinit var cameraProvider: ProcessCameraProvider
    private var camera: Camera? = null
    private var barcodeScanner: BarcodeScanner? = null
    private lateinit var cameraExecutor: ExecutorService

    private var isFlashOn = false
    private var userManuallyToggled = false
    private var scannedOnce = false
    private var processing = false
    private var proceedingToPay = false
    private var isFinishingFromPayment = false

    // Sensors & Gestures
    private lateinit var sensorManager: SensorManager
    private var lightSensor: Sensor? = null
    private lateinit var scaleGestureDetector: ScaleGestureDetector
    private lateinit var swipeDetector: android.view.GestureDetector
    private var isPinching = false

    // Result Tracking
    private var pendingAmount: Int = 0
    private var pendingCategory: String? = null
    private var pendingTitle: String = "UPI Payment"
    private var allocationHandled: Boolean = false
    private var currentChooser: BottomSheetDialog? = null
    private var selectedPaymentApp: String = "CRED"
    private var currentScanUpiId: String = "" // tracks the UPI ID currently being paid

    private val syncReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            currentChooser?.takeIf { it.isShowing }?.let { dialog: BottomSheetDialog ->
                refreshAllocationListSimple(dialog)
            }
        }
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        scaleGestureDetector.onTouchEvent(ev)

        // Manual Tap to Focus & Expose
        if (ev.action == MotionEvent.ACTION_UP && ev.pointerCount == 1) {
            val factory = previewView.meteringPointFactory
            val point = factory.createPoint(ev.x, ev.y)
            val action = FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
                .setAutoCancelDuration(3, TimeUnit.SECONDS)
                .build()
            camera?.cameraControl?.startFocusAndMetering(action)
        }

        if (ev.pointerCount > 1) isPinching = true
        if (ev.action == MotionEvent.ACTION_DOWN) isPinching = false

        if (ev.pointerCount == 1 && !isPinching && swipeDetector.onTouchEvent(ev)) {
            return true
        }
        return super.dispatchTouchEvent(ev)
    }

    @Deprecated("Deprecated in Java", ReplaceWith("startActivity(Intent(this, MainActivity::class.java)); finish()"))
    override fun onBackPressed() {
        super.onBackPressed()
        startActivity(Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        })
        finish()
        overridePendingTransition(R.anim.slide_in_right, R.anim.slide_out_left)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean("scannedOnce", scannedOnce)
        outState.putBoolean("processing", processing)
        outState.putBoolean("proceedingToPay", proceedingToPay)
        outState.putInt("pendingAmount", pendingAmount)
        outState.putString("pendingCategory", pendingCategory)
        outState.putString("pendingTitle", pendingTitle)
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
        scannedOnce = savedInstanceState.getBoolean("scannedOnce", scannedOnce)
        processing = savedInstanceState.getBoolean("processing", processing)
        proceedingToPay = savedInstanceState.getBoolean("proceedingToPay", proceedingToPay)
        pendingAmount = savedInstanceState.getInt("pendingAmount", pendingAmount)
        pendingCategory = savedInstanceState.getString("pendingCategory", pendingCategory)
        pendingTitle = savedInstanceState.getString("pendingTitle", pendingTitle)
    }

    override fun onResume() {
        super.onResume()
        if (isFinishingFromPayment || proceedingToPay) {
            window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
            findViewById<android.view.View>(R.id.scannerRoot)?.visibility = android.view.View.INVISIBLE
            return
        }
        lightSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
        // Returning here manually means the UPI app never handed a result back —
        // GPay in particular keeps the user in its own task, so `onActivityResult`
        // never fires. This used to clear the pending record and cancel the recovery
        // prompt, on the assumption that a manual return meant nothing happened. It
        // doesn't: the payment may well have gone through, and deleting the record
        // was the difference between asking the user and losing the expense silently.
        //
        // The record and its alarm are left alone. A prompt the user dismisses costs
        // far less than a payment that never reaches their history.
    }

    override fun onPause() {
        super.onPause()
        sensorManager.unregisterListener(this)
        if (proceedingToPay) {
            window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
            findViewById<android.view.View>(R.id.scannerRoot)?.visibility = android.view.View.INVISIBLE
        }
    }


    /**
     * Warns before letting a payment proceed on a device that looks compromised.
     *
     * This is the one screen where the [TamperCheck] signal is acted on, because
     * it is the one that moves money. Elsewhere the signal is only recorded.
     *
     * It warns rather than blocks, deliberately. Root is not evidence of an
     * attack on anybody but the device's own owner, and a hard block would deny
     * a payment feature to customers running a custom ROM in order to stop an
     * attacker who is only attacking themselves. The user is told plainly and
     * decides.
     *
     * To escalate to a hard block, replace the "Continue" button with `finish()`
     * and set `setCancelable(false)` — the detection side needs no changes.
     *
     * Shown once per process: repeating it on every scan would train people to
     * dismiss it without reading, which is worse than not showing it.
     */
    private fun warnIfDeviceCompromised() {
        if (tamperWarningShown) return

        val result = TamperCheck.evaluate(this)
        if (!result.isCompromised) return

        tamperWarningShown = true

        val reason = when {
            result.rooted -> "This device appears to be rooted."
            result.debuggerAttached -> "A debugger is attached to this app."
            else -> "This build of the app has been modified."
        }

        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Security warning")
            .setMessage(
                "$reason\n\nOn a device in this state, another app may be able to " +
                    "read or alter payment details before you confirm them. Your " +
                    "account data on our servers is unaffected.\n\n" +
                    "Continue only if you set this device up yourself."
            )
            .setPositiveButton("Continue") { d, _ -> d.dismiss() }
            .setNegativeButton("Go back") { _, _ -> finish() }
            .show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Determine the badge background and icon tint colors based on the theme
        val activeTheme = ThemeHelper.getCurrentTheme(this)

        // Use Edge-to-Edge and fitsSystemWindows to color the status bar and navigation bar.
        // The background color of scannerRoot will fill the status bar area automatically.

        androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = activeTheme == "White"
            isAppearanceLightNavigationBars = activeTheme == "White"
        }

        setContentView(R.layout.activity_scanner)

        warnIfDeviceCompromised()

        // Set root background dynamically to match status bar background
        findViewById<FrameLayout>(R.id.scannerRoot)?.setBackgroundColor(
            when (activeTheme) {
                "Blue" -> Color.parseColor("#000520")
                "White" -> Color.parseColor("#FFFFFF")
                else -> Color.parseColor("#000000")
            }
        )

        TutorialManager.showTutorialIfNeeded(
            this,
            "tut_scanner",
            "QR Scanner",
            "Scan from CashDash directly and record your payments\n\n1. Scan any UPI QR code\n2. Enter the amount and select an allocation\n3. Choose your payment app (Cred, GPay)\n4. Complete the payment in your UPI app and wait for 2-3 seconds\n5. We will automatically bring you back to CashDash and record the transaction\n\nGeneral tutorial for this page:\n\n1. Tap Undo button to pay again to the last scanned receiver\n2. Swipe right to left to go home page or use exit button at top\n\n*(Note: You can revisit these instructions anytime in the 'Help' section! Tap the Menu icon located next to 'Hello' on your Home dashboard to find it.)*"
        )

        previewView = findViewById(R.id.previewView)
        cameraExecutor = Executors.newSingleThreadExecutor()

        val btnClose = findViewById<ImageButton>(R.id.btnCloseScanner)
        val btnFlashlight = findViewById<ImageButton>(R.id.btnFlashlight)
        val btnGallery = findViewById<View>(R.id.btnGallery)
        val btnHistory = findViewById<ImageButton>(R.id.btnHistory)
        val btnMore = findViewById<ImageButton>(R.id.btnMore)

        val badgeBg = when (activeTheme) {
            "Blue" -> R.drawable.bg_circle_scanner_blue
            "White" -> R.drawable.bg_circle_scanner_white
            else -> R.drawable.bg_circle_black_transparent
        }
        val iconTint = when (activeTheme) {
            "White" -> Color.parseColor("#1A1A1A")
            else -> Color.WHITE
        }

        val imgGalleryIcon = findViewById<ImageView>(R.id.imgGalleryIcon)
        val tvGalleryText = findViewById<TextView>(R.id.tvGalleryText)

        btnClose.setBackgroundResource(badgeBg)
        btnHistory.setBackgroundResource(badgeBg)
        btnFlashlight.setBackgroundResource(badgeBg)
        btnMore.setBackgroundResource(badgeBg)

        btnClose.backgroundTintList = null
        btnHistory.backgroundTintList = null
        btnFlashlight.backgroundTintList = null
        btnMore.backgroundTintList = null

        if (activeTheme != "Blue") {
            btnGallery.setBackgroundResource(R.drawable.bg_capsule_white)
            imgGalleryIcon.setColorFilter(Color.BLACK, android.graphics.PorterDuff.Mode.SRC_IN)
            tvGalleryText.setTextColor(Color.BLACK)
        } else {
            btnGallery.setBackgroundResource(R.drawable.bg_capsule_scanner_blue)
            imgGalleryIcon.setColorFilter(Color.WHITE, android.graphics.PorterDuff.Mode.SRC_IN)
            tvGalleryText.setTextColor(Color.WHITE)
        }

        btnClose.imageTintList = android.content.res.ColorStateList.valueOf(iconTint)
        btnHistory.imageTintList = android.content.res.ColorStateList.valueOf(iconTint)
        btnFlashlight.imageTintList = android.content.res.ColorStateList.valueOf(if (isFlashOn && activeTheme != "White") Color.parseColor("#8BF7E6") else iconTint)
        btnMore.imageTintList = android.content.res.ColorStateList.valueOf(iconTint)

        btnFlashlight.setOnClickListener {
            isFlashOn = !isFlashOn
            userManuallyToggled = true
            camera?.cameraControl?.enableTorch(isFlashOn)
            updateFlashlightIcon()
        }

        btnMore.setOnClickListener {
            createShortcut()
        }

        val root = findViewById<View>(android.R.id.content)
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val density = resources.displayMetrics.density
            val topMarginPx = (25 * density).toInt()

            // Top buttons
            val closeParams = btnClose.layoutParams as FrameLayout.LayoutParams
            closeParams.topMargin = topMarginPx
            btnClose.layoutParams = closeParams

            val historyParams = btnHistory.layoutParams as FrameLayout.LayoutParams
            historyParams.topMargin = topMarginPx
            btnHistory.layoutParams = historyParams

            val flashParams = btnFlashlight.layoutParams as FrameLayout.LayoutParams
            flashParams.topMargin = topMarginPx
            flashParams.marginEnd = historyParams.marginEnd + (75 * density).toInt()
            btnFlashlight.layoutParams = flashParams

            val moreParams = btnMore.layoutParams as FrameLayout.LayoutParams
            moreParams.bottomMargin = (25 * density).toInt()
            btnMore.layoutParams = moreParams

            insets
        }

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        lightSensor = sensorManager.getDefaultSensor(Sensor.TYPE_LIGHT)

        scaleGestureDetector = ScaleGestureDetector(this, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val state = camera?.cameraInfo?.zoomState?.value ?: return false
                val currentZoom = state.zoomRatio
                val delta = detector.scaleFactor
                val maxZoom = state.maxZoomRatio
                val nextZoom = (currentZoom * delta).coerceIn(1.0f, maxZoom)
                camera?.cameraControl?.setZoomRatio(nextZoom)
                return true
            }
        })

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
        } else {
            startCamera()
        }

        btnClose.setOnClickListener { onBackPressed() }
        btnGallery.setOnClickListener { openGallery() }

        btnHistory.setOnClickListener {
            val localPrefs = ScanStore.get(this)
            val lastUpi = localPrefs.getString("last_upi", null)
            if (lastUpi != null) {
                scannedOnce = true
                if (::cameraProvider.isInitialized) cameraProvider.unbindAll()
                showAmountDialog(lastUpi)
            } else {
                toast("No previous scan history found")
            }
        }

        swipeDetector = android.view.GestureDetector(this, object : android.view.GestureDetector.SimpleOnGestureListener() {
            override fun onFling(e1: MotionEvent?, e2: MotionEvent, velocityX: Float, velocityY: Float): Boolean {
                if (e1 != null && e1.x - e2.x > 150 && Math.abs(velocityX) > 150) {
                    onBackPressed()
                    return true
                }
                return false
            }
        })


        val payAgainUpi = intent.getStringExtra("pay_again_upi")
        if (payAgainUpi != null) {
            scannedOnce = true
            previewView.post {
                if (::cameraProvider.isInitialized) cameraProvider.unbindAll()
                showAmountDialog(payAgainUpi)
            }
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()

            // Resolution Booster: Targeting 1080p (1920x1080) for high-distance scanning power.
            // 640x480 is standard, but 1080p gives the ML Kit engine 4x more pixel detail!
            val resolutionSelector = androidx.camera.core.resolutionselector.ResolutionSelector.Builder()
                .setResolutionStrategy(androidx.camera.core.resolutionselector.ResolutionStrategy(
                    android.util.Size(1920, 1080),
                    androidx.camera.core.resolutionselector.ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                ))
                .build()

            val preview = Preview.Builder()
                .setResolutionSelector(resolutionSelector)
                .build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

            // GPay-level Auto-Zoom integration with '2-Jump' Aggression Fix
            var lastAutoZoomTime = 0L
            val zoomSuggestionOptions = ZoomSuggestionOptions.Builder { zoomRatio ->
                val now = System.currentTimeMillis()
                if (now - lastAutoZoomTime < 600) return@Builder false
                lastAutoZoomTime = now

                val currentZoom = camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1.0f
                if (zoomRatio > currentZoom) {
                    val aggressiveRatio = (zoomRatio * 1.25f).coerceIn(1.0f, camera?.cameraInfo?.zoomState?.value?.maxZoomRatio ?: 10.0f)
                    camera?.cameraControl?.setZoomRatio(aggressiveRatio)

                    // RE-FOCUS LOCK: Immediately snap focus into the box at the new zoom level.
                    // This ensures we dont wait for standard AF to 'drift' into focus.
                    rootFocusAndMetering()
                    true
                } else false
            }.build()

            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .setZoomSuggestionOptions(zoomSuggestionOptions)
                .build()

            barcodeScanner = BarcodeScanning.getClient(options)

            val imageAnalysis = ImageAnalysis.Builder()
                .setResolutionSelector(resolutionSelector)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            imageAnalysis.setAnalyzer(cameraExecutor, { imageProxy -> scanQR(imageProxy) })

            try {
                cameraProvider.unbindAll()
                camera = cameraProvider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, imageAnalysis)

                // Flashlight fix: If sensor already toggled state to true before camera was ready, apply it now.
                if (isFlashOn) {
                    camera?.cameraControl?.enableTorch(true)
                }

                // The Magic GPay Exposure Fix: Aggressive center lock metering.
                // Washed-out images happen because standard metering tries to balance the whole scene.
                // We lock metering to the dead center, where the QR code usually is!
                rootFocusAndMetering()

            } catch (e: Exception) {
                toast("Failed to initialize camera")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun rootFocusAndMetering() {
        // GPay Settling Strategy:
        // We wait slightly longer (1.5s) to let the hardware's internal
        // "cold-start" CAF find a baseline before we force a lock.
        previewView.postDelayed({
            try {
                val expState = camera?.cameraInfo?.exposureState
                if (expState?.isExposureCompensationSupported == true) {
                    val range = expState.exposureCompensationRange
                    val targetIndex = (range.lower + (range.upper - range.lower) / 4).coerceIn(range.lower, 0)
                    camera?.cameraControl?.setExposureCompensationIndex(targetIndex)
                }

                val factory = previewView.meteringPointFactory
                val boxPoint = factory.createPoint(0.5f, 0.5f, 0.6f)

                // Adaptive Lock: Set a 7-second duration.
                // This 'Box Lock' is now the priority, but it will 'reset' and refresh
                // every 7 seconds if the user hasn't scanned anything yet, preventing
                // the camera from getting stuck in a blurred state.
                val action = FocusMeteringAction.Builder(boxPoint, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
                    .setAutoCancelDuration(7, TimeUnit.SECONDS)
                    .build()

                camera?.cameraControl?.startFocusAndMetering(action)
            } catch (e: Exception) {}
        }, 1500)
    }

    @androidx.camera.core.ExperimentalGetImage
    private fun scanQR(proxy: ImageProxy) {
        if (processing || scannedOnce) { proxy.close(); return }
        processing = true

        val media = proxy.image ?: return proxy.close()
        val img = InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees)

        barcodeScanner?.process(img)?.addOnSuccessListener { codes ->
            for (b in codes) {
                val upi = b.rawValue ?: continue
                if (upi.contains("upi://pay")) {
                    scannedOnce = true
                    cameraProvider.unbindAll()
                    successBeep()
                    shake()
                    showAmountDialog(upi)
                    return@addOnSuccessListener // prevent multiple decodes
                }
            }
        }?.addOnCompleteListener {
            proxy.close()
            processing = false
        }
    }

    override fun onStart() {
        super.onStart()
        LocalBroadcastManager.getInstance(this).registerReceiver(
            syncReceiver, android.content.IntentFilter(FirestoreSyncManager.ACTION_SYNC_UPDATE)
        )
    }

    override fun onStop() {
        super.onStop()
        LocalBroadcastManager.getInstance(this).unregisterReceiver(syncReceiver)
        sensorManager.unregisterListener(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
        barcodeScanner?.close()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_LIGHT) {
            val lux = event.values[0]
            if (!userManuallyToggled) {
                if (lux < 5f && !isFlashOn) {
                    isFlashOn = true
                    camera?.cameraControl?.enableTorch(true)
                    updateFlashlightIcon()
                    // Stop listening after auto-turn-on to prevent feedback loops/flickering
                    userManuallyToggled = true
                    sensorManager.unregisterListener(this)
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun updateFlashlightIcon() {
        val btnFlashlight = findViewById<ImageButton>(R.id.btnFlashlight)
        btnFlashlight.setImageResource(if (isFlashOn) R.drawable.ic_flashlight_on else R.drawable.ic_flashlight_off)
        val activeTheme = ThemeHelper.getCurrentTheme(this)
        val normalTint = if (activeTheme == "White") Color.parseColor("#1A1A1A") else Color.WHITE
        btnFlashlight.imageTintList = android.content.res.ColorStateList.valueOf(if (isFlashOn) Color.parseColor("#8BF7E6") else normalTint)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQUEST && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            toast("Camera permission is required")
            finish()
        }
    }

    private fun openGallery() {
        startActivityForResult(Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI), GALLERY_PICK)
    }

    private fun parseUpiResponse(response: String): Map<String, String> {
        val map = mutableMapOf<String, String>()
        val queryString = if (response.contains("?")) response.substringAfter("?") else response
        if (queryString.isNotEmpty()) {
            val pairs = queryString.split("&")
            for (pair in pairs) {
                val parts = pair.split("=")
                if (parts.size >= 2) {
                    map[parts[0]] = parts[1]
                }
            }
        }
        return map
    }

    override fun onActivityResult(req: Int, res: Int, data: Intent?) {
        super.onActivityResult(req, res, data)
        if (req == PAYMENT_REQ) {



            // Gather potential response sources
            val responseExtra = data?.getStringExtra("response") ?: ""
            val dataUriString = data?.data?.toString() ?: ""

            val rawResponse = when {
                responseExtra.isNotEmpty() -> responseExtra
                dataUriString.isNotEmpty() -> dataUriString
                else -> ""
            }

            // The UPI app names its own decline reason in `responseCode` (U30, U69,
            // XH, ZM and so on). Nothing below reads it, so on a debug build it goes
            // to logcat, which is the difference between diagnosing a failed payment
            // and guessing at it.
            logPaymentDebug("result res=$res raw=$rawResponse")

            val params = parseUpiResponse(rawResponse)

            // Helper to retrieve params case-insensitively and check direct extras
            fun getParam(vararg keys: String): String {
                for (key in keys) {
                    val value = params.entries.find { it.key.equals(key, ignoreCase = true) }?.value
                    if (!value.isNullOrEmpty()) return value
                }
                for (key in keys) {
                    val value = data?.getStringExtra(key)
                    if (!value.isNullOrEmpty()) return value
                }
                return ""
            }

            val status = getParam("Status", "status")

            // Three outcomes, not two.
            //
            // SUBMITTED (and PENDING) mean the UPI app handed the request onward and
            // does not yet know how it ended. That is not success. Counting it as one
            // debited the wallet for money that never moved — backing out of PhonePe
            // produced `Status=Submitted&txnId=null` and still logged an expense.
            //
            // `res` is deliberately not part of the success test. UPI apps return
            // RESULT_CANCELED alongside a perfectly good payload (PhonePe does exactly
            // this), so requiring RESULT_OK would reject real successes. It is only
            // trusted when there is no payload at all to read.
            val confirmedSuccess =
                status.equals("SUCCESS", ignoreCase = true) ||
                    (status.isEmpty() && rawResponse.contains("SUCCESS", ignoreCase = true))

            val confirmedFailure =
                status.equals("FAILURE", ignoreCase = true) ||
                    status.equals("FAILED", ignoreCase = true) ||
                    (rawResponse.isEmpty() && res == Activity.RESULT_CANCELED)

            // Restore globals if the activity was recreated
            val prefs = getSharedPreferences("PendingTransactionPrefs", Context.MODE_PRIVATE)
            if (pendingAmount == 0) {
                pendingAmount = prefs.getString("pending_amount", "0")?.toDoubleOrNull()?.toInt() ?: 0
                pendingCategory = prefs.getString("pending_category", "no choice")
                pendingTitle = prefs.getString("pending_title", "") ?: ""
                selectedPaymentApp = prefs.getString("pending_app", "CRED") ?: "CRED"
            }

            logPaymentDebug(
                "verdict=" + when {
                    confirmedSuccess -> "SUCCESS (expense written)"
                    confirmedFailure -> "FAILED (nothing written)"
                    else -> "PENDING (nothing written, recovery prompt kept)"
                } + " status='$status'"
            )

            isFinishingFromPayment = true

            if (confirmedSuccess || confirmedFailure) {
                // We know how it ended, so the pending record and its recovery prompt
                // have done their job.
                prefs.edit().clear().apply()
                androidx.core.app.NotificationManagerCompat.from(this).cancel(999)
                val alarmIntent = android.content.Intent(this, PaymentRecoveryAlarmReceiver::class.java)
                val pendingIntent = android.app.PendingIntent.getBroadcast(this, 99, alarmIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
                val alarmManager = getSystemService(android.content.Context.ALARM_SERVICE) as android.app.AlarmManager
                alarmManager.cancel(pendingIntent)

                if (confirmedSuccess) redirectSuccess() else redirectFailed()
            } else {
                // Unknown. Leave the pending record and its alarm in place so the
                // recovery prompt can ask the user, which is the only signal we have.
                redirectPending()
            }
        }
        if (req == GALLERY_PICK && res == Activity.RESULT_OK) {
            data?.data?.let { scanGalleryQR(it) }
        }
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun scanGalleryQR(uri: Uri) {
        try {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }

            var inSampleSize = 1
            if (options.outHeight > 1024 || options.outWidth > 1024) {
                val halfHeight = options.outHeight / 2
                val halfWidth = options.outWidth / 2
                while (halfHeight / inSampleSize >= 1024 && halfWidth / inSampleSize >= 1024) inSampleSize *= 2
            }

            options.inJustDecodeBounds = false
            options.inSampleSize = inSampleSize
            val bmp = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }

            if (bmp == null) { toast("⚠️ Could not load image"); return }

            val img = InputImage.fromBitmap(bmp, 0)
            BarcodeScanning.getClient().process(img).addOnSuccessListener { codes ->
                for (b in codes) {
                    val upi = b.rawValue ?: continue
                    if (upi.contains("upi://pay")) {
                        successBeep()
                        showAmountDialog(upi)
                        return@addOnSuccessListener
                    }
                }
                toast("⚠️ No UPI QR found in image")
            }.addOnFailureListener { toast("⚠️ Error scanning image") }
        } catch (e: Exception) {}
    }

    // ------------------------------------------------------------------- DIALOG PAYMENT
    @SuppressLint("MissingInflatedId")
    private fun showAmountDialog(upi: String) {
        try {
            proceedingToPay = false
            val name = (decode(getParam(upi,"pn")) ?: "Unknown").replace("|", "-")
            val id = (decode(getParam(upi,"pa")) ?: "Unknown").replace("|", "-")

            if (upi.contains("upi://pay")) {
                ScanStore.get(this).edit().putString("last_upi", upi).apply()
                FirestoreSyncManager.pushAllDataToCloud(this)
            }

            val dialog = BottomSheetDialog(this, ThemeHelper.getBottomSheetTheme(this))
            currentChooser = dialog
            val view = layoutInflater.inflate(R.layout.layout_payment_bottom_sheet, null)
            dialog.setContentView(view)

            // Apply theme-aware top border color
            view.findViewById<View>(R.id.viewTopBorder)?.setBackgroundColor(
                if (ThemeHelper.isWhiteTheme(this))
                    android.graphics.Color.parseColor("#33000000") // subtle dark for white theme
                else
                    android.graphics.Color.parseColor("#FFFFFF")  // white for dark/blue theme
            )
            
            view.findViewById<View>(R.id.viewDragHandle)?.setBackgroundColor(
                if (ThemeHelper.isWhiteTheme(this))
                    android.graphics.Color.parseColor("#33000000") // dark handle for white theme
                else
                    android.graphics.Color.parseColor("#40FFFFFF")  // white handle for dark/blue theme
            )

            pendingAmount = 0
            pendingCategory = null
            pendingTitle = "To: $name"
            allocationHandled = false

            // Check if this UPI ID has a remembered allocation
            val upiId = (decode(getParam(upi, "pa")) ?: "").trim().lowercase()
            currentScanUpiId = upiId
            val savedAlloc = if (upiId.isNotEmpty()) {
                getSharedPreferences("UpiAllocationPrefs", MODE_PRIVATE).getString("ALLOC_$upiId", null)
            } else null

            val tvInfo = view.findViewById<TextView>(R.id.tvReceiverInfo)
            val isPhonePayment = !id.contains("@") && id.all { it.isDigit() }
            tvInfo.text = if (isPhonePayment) "Receiver: $name" else "Receiver: $name\nUPI ID: $id"

            val etAmount = view.findViewById<EditText>(R.id.etPaymentAmount)
            val tvAllocation = view.findViewById<TextView>(R.id.tvAllocationLabel)
            val btnChoose = view.findViewById<Button>(R.id.btnChooseAllocation)

            val btnCred = view.findViewById<Button>(R.id.btnPayCred)
            val btnGPay = view.findViewById<Button>(R.id.btnPayGPay)

            val paymentActionContainer = view.findViewById<LinearLayout>(R.id.paymentActionContainer)
            val btnPayInitiate = view.findViewById<Button>(R.id.btnPayInitiate)
            val tvWalletBalance = view.findViewById<TextView>(R.id.tvWalletBalance)

            // Auto-Fill Amount from QR
            val qrAmount = getParam(upi, "am")
            if (!qrAmount.isNullOrEmpty()) {
                val parsedDouble = qrAmount.toDoubleOrNull() ?: 0.0
                if (parsedDouble > 0) {
                    val amountText = if (parsedDouble % 1.0 == 0.0) {
                        parsedDouble.toInt().toString()
                    } else {
                        qrAmount
                    }
                    etAmount.setText(amountText)
                    btnPayInitiate.text = "Pay ₹$amountText"
                }
            }

            val balance = WalletStore.get(this).getInt("wallet_balance", 0)
            tvWalletBalance.text = "Wallet Balance: ₹$balance"

            btnCred.visibility = View.VISIBLE
            btnGPay.visibility = View.VISIBLE

            // Pre-fill saved allocation if available
            if (savedAlloc != null && !savedAlloc.equals("no choice", ignoreCase = true)) {
                val categories = getSharedPreferences("CategoryPrefs", MODE_PRIVATE)
                    .getStringSet("categories", emptySet()) ?: emptySet()

                // Case-insensitive match: handles re-added categories like "medical"→"Medical"
                val matchedCategory = categories.find { it.equals(savedAlloc, ignoreCase = true) }

                if (matchedCategory != null) {
                    // If re-added with different case, update the stored mapping to match current name
                    if (matchedCategory != savedAlloc) {
                        saveUpiAllocation(upiId, matchedCategory)
                    }
                    pendingCategory = matchedCategory
                    allocationHandled = true
                    tvAllocation.text = "Allocated to: $matchedCategory"
                    tvAllocation.visibility = View.VISIBLE
                    btnChoose.text = "Change"
                    btnChoose.visibility = View.VISIBLE
                    paymentActionContainer.visibility = View.VISIBLE
                    btnPayInitiate.visibility = View.GONE
                } else {
                    // Category was deleted and not re-added — show fresh chooser flow
                    tvAllocation.visibility = View.GONE
                    btnChoose.visibility = View.GONE
                }
            } else {
                tvAllocation.visibility = View.GONE
                btnChoose.visibility = View.GONE
            }

            etAmount.addTextChangedListener(object : android.text.TextWatcher {
                override fun afterTextChanged(s: android.text.Editable?) {
                    val amt = s.toString()
                    btnPayInitiate.text = if (amt.isNotEmpty()) "Pay ₹$amt" else "Pay ₹0"
                }
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            })

            btnPayInitiate.setOnClickListener {
                val amtStr = etAmount.text.toString()
                if (amtStr.isEmpty() || (amtStr.toDoubleOrNull()?.toInt() ?: 0) == 0) {
                    toast("Please enter an amount")
                    return@setOnClickListener
                }
                showAllocationChooser(dialog, tvAllocation, btnChoose, paymentActionContainer, btnPayInitiate)
            }

            btnChoose.setOnClickListener { showAllocationChooser(dialog, tvAllocation, btnChoose, paymentActionContainer, btnPayInitiate) }

            btnCred.setOnClickListener {
                if (!allocationHandled) { toast("Please select an allocation or skip"); return@setOnClickListener }
                proceedingToPay = true
                val amtStr = etAmount.text.toString()
                if (amtStr.isEmpty()) return@setOnClickListener
                pendingAmount = amtStr.toDoubleOrNull()?.toInt() ?: 0
                selectedPaymentApp = "CRED"
                dialog.dismiss()
                payUPI(upi, amtStr, "com.dreamplug.androidapp")
            }

            // "Other UPI" stays disabled. Every app except CRED either refuses the
            // intent outright (GPay, PhonePe, Paytm, BHIM return no transaction at
            // all) or accepts it and has the payment declined downstream (supermoney
            // creates a real txnId, then the receiver's bank stops it as suspected
            // fraud). The same QR scanned natively inside those apps succeeds, so the
            // difference is provenance, not anything in the URI we build.
            val layoutComingSoonToast = view.findViewById<LinearLayout>(R.id.layoutComingSoonToast)
            var comingSoonRunnable: Runnable? = null
            val comingSoonHandler = android.os.Handler(android.os.Looper.getMainLooper())

            btnGPay.setOnClickListener {
                layoutComingSoonToast?.let { toastView ->
                    comingSoonRunnable?.let { comingSoonHandler.removeCallbacks(it) }
                    toastView.animate().cancel()
                    toastView.alpha = 0f
                    toastView.visibility = View.VISIBLE
                    toastView.animate().alpha(1f).setDuration(200).start()

                    val runnable = Runnable {
                        toastView.animate().alpha(0f).setDuration(300).withEndAction {
                            toastView.visibility = View.GONE
                        }.start()
                    }
                    comingSoonRunnable = runnable
                    comingSoonHandler.postDelayed(runnable, 2000)
                }
            }

            dialog.setOnDismissListener {
                if (!proceedingToPay) {
                    scannedOnce = false
                    startCamera()
                }
            }
            dialog.show()
        } catch (e: Exception) { toast("⚠️ Error opening payment dialog") }
    }

    private fun showAllocationChooser(parentDialog: BottomSheetDialog, label: TextView, btn: Button, paymentContainer: LinearLayout, btnPayInit: Button) {
        val chooser = BottomSheetDialog(this, ThemeHelper.getBottomSheetTheme(this))
        currentChooser = chooser
        val view = layoutInflater.inflate(R.layout.layout_allocation_chooser_bottom_sheet, null)
        chooser.setContentView(view)

        // Store references in tags for sync refresh
        view.tag = arrayOf(parentDialog, label, btn, paymentContainer, btnPayInit)

        refreshAllocationList(chooser, parentDialog, label, btn, paymentContainer, btnPayInit)

        chooser.show()
        val bottomSheet = chooser.findViewById<View>(com.google.android.material.R.id.design_bottom_sheet)
        if (bottomSheet != null) {
            val behavior = com.google.android.material.bottomsheet.BottomSheetBehavior.from(bottomSheet as FrameLayout)
            behavior.state = com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
            behavior.skipCollapsed = true
        }
    }

    private fun refreshAllocationListSimple(chooser: BottomSheetDialog) {
        val view = chooser.findViewById<View>(R.id.allocationListContainer)?.parent as? View ?: return
        val tags = view.tag as? Array<*> ?: return
        if (tags.size < 5) return

        refreshAllocationList(
            chooser,
            tags[0] as BottomSheetDialog,
            tags[1] as TextView,
            tags[2] as Button,
            tags[3] as LinearLayout,
            tags[4] as Button
        )
    }

    private fun refreshAllocationList(chooser: BottomSheetDialog, parentDialog: BottomSheetDialog, label: TextView, btn: Button, paymentContainer: LinearLayout, btnPayInit: Button) {
        val container = chooser.findViewById<LinearLayout>(R.id.allocationListContainer) ?: return
        container.removeAllViews()
        val density = resources.displayMetrics.density
        val prefs = getSharedPreferences("CategoryPrefs", MODE_PRIVATE)
        val spentPrefs = getSharedPreferences("GraphData", MODE_PRIVATE)

        val btnCreateNew = Button(this).apply {
            text = "+ Create New Allocation"
            setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
            isAllCaps = false
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, context.resources.getDimension(R.dimen.text_subhead))
            background = ContextCompat.getDrawable(context, com.cash.dash.ThemeHelper.getDrawable(context, R.drawable.bg_glass_3d))
            stateListAnimator = null
            elevation = 0f
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (54 * density).toInt()).apply { setMargins(0, 0, 0, 30) }
            setOnClickListener { showCreateCategoryDialog(chooser, label, btn, paymentContainer, btnPayInit) }
        }
        container.addView(btnCreateNew)

        val btnSkip = Button(this).apply {
            text = "Skip allocation"
            setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
            isAllCaps = false
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, context.resources.getDimension(R.dimen.text_subhead))
            background = ContextCompat.getDrawable(context, com.cash.dash.ThemeHelper.getDrawable(context, R.drawable.bg_glass_3d_red))
            stateListAnimator = null
            elevation = 0f
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (54 * density).toInt()).apply { setMargins(0, 0, 0, 30) }
            setOnClickListener {
                pendingCategory = null
                allocationHandled = true
                // Register "no choice" for this UPI to clear/reset the saved allocation preference
                saveUpiAllocation(currentScanUpiId, "no choice")
                label.text = "No allocation selected"
                label.visibility = View.VISIBLE
                btn.text = "Choose"
                btn.visibility = View.VISIBLE
                paymentContainer.visibility = View.VISIBLE
                btnPayInit.visibility = View.GONE
                chooser.dismiss()
            }
        }
        container.addView(btnSkip)

        val categories = prefs.getStringSet("categories", emptySet()) ?: emptySet()
        if (categories.isEmpty()) {
            container.addView(TextView(this).apply {
                text = "No allocated categories found. Set limits in Rigor Tracker first."
                setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
                setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, context.resources.getDimension(R.dimen.text_subhead))
                setPadding(20, 20, 20, 20)
            })
        } else {
            val sortedList = categories.filter { it.isNotBlank() }.sortedBy { it.lowercase() }

            for (cat in sortedList) {
                val row = layoutInflater.inflate(R.layout.item_rigor_category, container, false)
                val txtName = row.findViewById<TextView>(R.id.categoryName)
                val spentBar = row.findViewById<View>(R.id.spentBar)
                val progressOuter = row.findViewById<View>(R.id.progressOuter)
                val txtSpent = row.findViewById<TextView>(R.id.txtSpent)
                val txtLimit = row.findViewById<TextView>(R.id.txtLimit)
                val iconView = row.findViewById<ImageView>(R.id.categoryIcon)

                iconView.setImageResource(CategoryIconHelper.getIconForCategory(this, cat))
                txtName.text = cat

                val limit = prefs.getInt("LIMIT_$cat", 0)
                val spent = spentPrefs.getFloat("SPENT_$cat", 0f)

                txtSpent.text = "Spent: ₹${spent.toInt()}"
                txtLimit.text = if (limit > 0) "Limit: ₹$limit" else "Limit: —"

                val progress = if (limit > 0) (spent / limit).coerceIn(0f, 1f) else 0f

                row.post {
                    val maxWidth = progressOuter.width
                    val targetWidth = (maxWidth * progress).toInt()

                    val anim = android.animation.ValueAnimator.ofInt(0, targetWidth)
                    anim.addUpdateListener { valueAnimator ->
                        val value = valueAnimator.animatedValue as Int
                        spentBar.layoutParams.width = value
                        spentBar.requestLayout()
                    }
                    anim.duration = 500
                    anim.start()

                    spentBar.setBackgroundResource(if (limit > 0 && spent >= limit) R.drawable.bg_glass_progress_fill_red else R.drawable.bg_glass_progress_fill)
                }

                row.setOnClickListener {
                    // Save UPI -> allocation mapping for future auto-fill
                    saveUpiAllocation(currentScanUpiId, cat)
                    pendingCategory = cat
                    allocationHandled = true
                    label.text = "Allocated to: $cat"
                    label.visibility = View.VISIBLE
                    btn.text = "Change"
                    btn.visibility = View.VISIBLE
                    paymentContainer.visibility = View.VISIBLE
                    btnPayInit.visibility = View.GONE
                    chooser.dismiss()
                }
                container.addView(row)
            }
        }
    }


    private fun showCreateCategoryDialog(parentDialog: BottomSheetDialog, label: TextView, btn: Button, paymentContainer: LinearLayout, btnPayInit: Button) {
        val density = resources.displayMetrics.density
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val p = (28 * density).toInt()
            setPadding(p, p, p, (24 * density).toInt())
            setBackgroundResource(com.cash.dash.ThemeHelper.getDrawable(context, R.drawable.bg_transaction))
        }

        val titleView = TextView(this).apply {
            text = "New Allocation"
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, context.resources.getDimension(R.dimen.text_title))
            setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, (20 * density).toInt())
        }
        box.addView(titleView)

        val inputName = EditText(this).apply {
            hint = "Category Name (e.g. Travel)"
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
            setHintTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textMutedColor))
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, (16 * density).toInt())
            }
        }
        box.addView(inputName)

        val inputLimit = EditText(this).apply {
            hint = "Enter limit (optional)"
            inputType = android.text.InputType.TYPE_CLASS_NUMBER
            setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
            setHintTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textMutedColor))
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                setMargins(0, 0, 0, (28 * density).toInt())
            }
        }
        box.addView(inputLimit)

        val buttonContainer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            clipChildren = false
            clipToPadding = false
        }

        val dialog = AlertDialog.Builder(this)
            .setView(box)
            .create()
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)

        val btnCancel = android.widget.Button(this).apply {
            text = "Cancel"
            isAllCaps = false
            setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
            val tv = android.util.TypedValue()
            context.theme.resolveAttribute(R.attr.cardBackground, tv, true)
            background = androidx.core.content.ContextCompat.getDrawable(context, tv.resourceId)
            stateListAnimator = null
            elevation = 0f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins(0, 0, (8 * density).toInt(), 0)
            }
            minHeight = (54 * density).toInt()
            setOnClickListener { dialog.dismiss() }
        }
        buttonContainer.addView(btnCancel)

        val btnSave = android.widget.Button(this).apply {
            text = "Create"
            isAllCaps = false
            setTextColor(com.cash.dash.ThemeHelper.resolveColorAttr(this@ScannerActivity, R.attr.textPrimaryColor))
            val tv = android.util.TypedValue()
            context.theme.resolveAttribute(R.attr.cardBackground, tv, true)
            background = androidx.core.content.ContextCompat.getDrawable(context, tv.resourceId)
            stateListAnimator = null
            elevation = 0f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                setMargins((8 * density).toInt(), 0, 0, 0)
            }
            minHeight = (54 * density).toInt()

            setOnClickListener {
                val catName = inputName.text.toString().trim().replace("|", "-")
                if (catName.equals("Overall", ignoreCase = true)) {
                    toast("'Overall' is a reserved name")
                    return@setOnClickListener
                }
                if (catName.isNotEmpty()) {
                    val prefs = getSharedPreferences("CategoryPrefs", MODE_PRIVATE)
                    val editor = prefs.edit()

                    val existing = prefs.getStringSet("categories", emptySet())?.toMutableSet() ?: mutableSetOf()

                    val limitStr = inputLimit.text.toString()
                    val newLimit = if (limitStr.isNotEmpty()) limitStr.toIntOrNull() ?: 0 else 0

                    val walletPrefs = WalletStore.get(this@ScannerActivity)
                    val totalBalance = walletPrefs.getInt("initial_balance", 0).coerceAtLeast(0)

                    var currentSumOfLimits = 0
                    for (cat in existing) {
                        currentSumOfLimits += prefs.getInt("LIMIT_$cat", 0)
                    }
                    val maxAllowed = totalBalance - currentSumOfLimits

                    if (newLimit > maxAllowed) {
                        toast("Exceeds total balance! Max allowed: ₹$maxAllowed")
                        return@setOnClickListener
                    }

                    existing.add(catName)
                    editor.putStringSet("categories", existing)

                    if (newLimit > 0) {
                        editor.putInt("LIMIT_$catName", newLimit)
                    }
                    editor.apply()

                    FirestoreSyncManager.pushAllDataToCloud(this@ScannerActivity)
                    parentDialog.dismiss()
                    showAllocationChooser(parentDialog, label, btn, paymentContainer, btnPayInit)
                    toast("Created $catName")
                    dialog.dismiss()
                }
            }
        }
        buttonContainer.addView(btnSave)
        box.addView(buttonContainer)

        dialog.show()
    }

    /**
     * Returns the scanned QR with the user's amount applied and nothing else changed.
     *
     * This used to parse the QR and rebuild the URI from its parts, mangling it
     * three ways: `Uri.Builder` re-encodes every value (the '@' in a VPA became
     * %40), the query order changed, and a synthetic `tr` was appended. A `tr` is a
     * *merchant* transaction reference, so fabricating one made every payment assert
     * a merchant context CashDash cannot back up.
     *
     * To be clear about what this does and does not fix: it is not why payments to
     * GPay, PhonePe and Paytm fail. Testing showed those are refused on provenance —
     * the payer app and the receiving bank both distinguish a natively scanned
     * payment from a handed-off one, and no URI satisfies them. But a rebuilt URI is
     * wrong on its own terms, and would corrupt a signed merchant QR the moment one
     * arrived.
     *
     * So: never parse, never re-encode, never reorder, and never add a parameter
     * the payee did not put there. The amount is spliced into the raw query string
     * and everything else is handed on byte-for-byte, which keeps `sign`, `mc`,
     * `orgid` and any acquirer-issued `tr` exactly as scanned.
     */
    private fun updateUpiAmount(upiUri: String, newAmount: String): String {
        val amount = newAmount.toDoubleOrNull() ?: return upiUri
        val formattedAmt = String.format(java.util.Locale.US, "%.2f", amount)

        val queryStart = upiUri.indexOf('?')
        if (queryStart < 0) return "$upiUri?am=$formattedAmt"

        val prefix = upiUri.substring(0, queryStart)
        val query = upiUri.substring(queryStart + 1)
        if (query.isEmpty()) return "$prefix?am=$formattedAmt"

        val pairs = query.split("&")

        // A signed QR that already carries an amount is a dynamic merchant QR: the
        // amount is part of what was signed, so overwriting it invalidates `sign`.
        // Leave it entirely alone and let the UPI app charge what the merchant set.
        // A signed QR with no amount is a static one, where the payer supplies the
        // amount and the signature does not cover it, so that case falls through.
        val hasSign = pairs.any { it.substringBefore('=').equals("sign", ignoreCase = true) }
        val hasFixedAmount = pairs.any {
            it.substringBefore('=').equals("am", ignoreCase = true) &&
                it.substringAfter('=', "").isNotEmpty()
        }
        if (hasSign && hasFixedAmount) return upiUri

        var replaced = false
        val rebuilt = pairs.joinToString("&") { pair ->
            if (pair.substringBefore('=').equals("am", ignoreCase = true)) {
                replaced = true
                "am=$formattedAmt"
            } else {
                pair
            }
        }

        return if (replaced) "$prefix?$rebuilt" else "$prefix?$rebuilt&am=$formattedAmt"
    }

    private fun scheduleRecoveryNotification(amount: String, upiId: String) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        val intent = Intent(this, PaymentRecoveryAlarmReceiver::class.java)

        val pendingIntent = android.app.PendingIntent.getBroadcast(
            this,
            99,
            intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + 60_000 // Exact 1 minute

        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
                } else {
                    // Fallback if permission is denied
                    alarmManager.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
                }
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            } else {
                alarmManager.setExact(android.app.AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
            }
        } catch (e: SecurityException) {
            // Fallback for extreme OEM modifications
            alarmManager.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, triggerTime, pendingIntent)
        }
    }

    private fun logPendingTransaction(amount: String, upiId: String, fullUri: String) {
        val prefs = getSharedPreferences("PendingTransactionPrefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("has_pending", true)
            .putString("pending_amount", amount)
            .putString("pending_upi", upiId)
            .putString("pending_upi_uri", fullUri)
            .putLong("pending_time", System.currentTimeMillis())
            .putString("pending_category", pendingCategory ?: "no choice")
            .putString("pending_title", pendingTitle)
            .putString("pending_app", selectedPaymentApp)
            .apply()

        scheduleRecoveryNotification(amount, upiId)
    }

    /**
     * Hands the payment off to a UPI app. A null [pkg] opens the system chooser so
     * any installed UPI app can take it; a non-null one targets that app directly.
     */
    private fun payUPI(upi: String, amt: String, pkg: String?) {
        try {
            val paMatch = Regex("[?&]pa=([^&]+)").find(upi)?.groupValues?.get(1)
            if (paMatch == null || paMatch.isEmpty()) { toast("Invalid QR: Missing UPI ID"); return }
            val cleanPaMatch = decode(paMatch) ?: paMatch

            val p2pUriString = updateUpiAmount(upi, amt)
            logPaymentDebug("launch pkg=${pkg ?: "chooser"} uri=$p2pUriString")

            val baseIntent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(p2pUriString)
                if (pkg != null) setPackage(pkg)
            }

            if (pkg == null) {
                logPendingTransaction(amt, cleanPaMatch, p2pUriString)
                startActivityForResult(Intent.createChooser(baseIntent, "Pay with"), PAYMENT_REQ)
            } else if (packageManager.resolveActivity(baseIntent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                logPendingTransaction(amt, cleanPaMatch, p2pUriString)
                startActivityForResult(baseIntent, PAYMENT_REQ)
            } else {
                packageManager.getLaunchIntentForPackage(pkg)?.let {
                    it.action = Intent.ACTION_VIEW
                    it.data = Uri.parse(p2pUriString)
                    logPendingTransaction(amt, cleanPaMatch, p2pUriString)
                    startActivityForResult(it, PAYMENT_REQ)
                } ?: toast("App not installed on this device")
            }
        } catch (e: Exception) { toast("Failed to launch payment app") }
    }


    private fun redirectSuccess() {
        if (pendingAmount > 0) {
            saveExpense(pendingCategory ?: "no choice", pendingAmount, pendingTitle)
        }
        val lastUpi = ScanStore.get(this).getString("last_upi", "") ?: ""
        val recipientUpi = (decode(getParam(lastUpi, "pa")) ?: "")

        val intent = Intent(this, SuccessActivity::class.java).apply {
            putExtra("recipient_name", pendingTitle.removePrefix("To: "))
            putExtra("recipient_upi_id", recipientUpi)
            putExtra("amount", pendingAmount)
            putExtra("payment_app", selectedPaymentApp)
            putExtra("upi_uri", lastUpi)
            putExtra("timestamp", System.currentTimeMillis())
            flags = Intent.FLAG_ACTIVITY_NO_ANIMATION
        }
        startActivity(intent)
        finish()
        overridePendingTransition(0, 0)
    }

    private fun redirectFailed() {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("payment_detected", true)
            putExtra("result", "Transaction Failed")
            putExtra("payment_status", "failed")
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION
        }
        startActivity(intent)
        finish()
        overridePendingTransition(0, 0)
    }

    /**
     * The UPI app came back without telling us how the payment ended — typically a
     * `SUBMITTED` status, which means the bank has the request but the outcome is
     * still open. Nothing is written to history here; the pending record stays put
     * and the recovery prompt asks the user once the dust settles.
     */
    private fun redirectPending() {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("payment_detected", true)
            putExtra("result", "Transaction Pending")
            putExtra("payment_status", "pending")
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION
        }
        startActivity(intent)
        finish()
        overridePendingTransition(0, 0)
    }

    private fun saveExpense(category: String, amount: Int, titleText: String) {
        val prefs = getSharedPreferences("GraphData", MODE_PRIVATE)
        val weeklyPrefs = getSharedPreferences("CategoryWeekData", MODE_PRIVATE)
        val editor = prefs.edit()
        val weekEditor = weeklyPrefs.edit()

        val cal = Calendar.getInstance().apply { setFirstDayOfWeek(Calendar.MONDAY); setMinimalDaysInFirstWeek(1) }
        val timestamp = cal.timeInMillis.toString()

        val dayIndex = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7
        val timestampLong = cal.timeInMillis

        HistoryDataManager.saveTransaction(this, titleText, amount.toFloat(), category, timestampLong)

        // Save Scanner Metadata (UPI and App) for history lookup
        val lastUpi = ScanStore.get(this).getString("last_upi", "") ?: ""
        getSharedPreferences("ScannerMetadataPrefs", MODE_PRIVATE).edit()
            .putString("UPI_${timestampLong}", lastUpi)
            .putString("APP_${timestampLong}", selectedPaymentApp)
            .apply()
    }

    private fun getParam(t: String, k: String): String? {
        return try {
            val uri = android.net.Uri.parse(t)
            uri.getQueryParameter(k.lowercase())
                ?: uri.getQueryParameter(k.uppercase())
                ?: Regex("(?i)$k=([^&]*)").find(t)?.groupValues?.get(1)
        } catch (e: Exception) {
            Regex("(?i)$k=([^&]*)").find(t)?.groupValues?.get(1)
        }
    }
    /**
     * Payment-flow tracing, debug builds only.
     *
     * A UPI URI carries the payee's VPA and, on a personal QR, their name, so this
     * must never reach a release build — the log sanitisation pass in 8427d3f
     * stripped exactly this kind of output. `BuildConfig.DEBUG` is a compile-time
     * constant, so R8 removes the calls entirely from release.
     */
    private fun logPaymentDebug(message: String) {
        if (BuildConfig.DEBUG) android.util.Log.d("CashDashUPI", message)
    }

    private fun decode(v: String?) = v?.let { URLDecoder.decode(it, "UTF-8") }
    private fun toast(s: String, gravity: Int? = null, yOffset: Int = 0) = ToastHelper.showToast(this, s, Toast.LENGTH_SHORT, gravity, yOffset)
    private fun successBeep() { try { (getSystemService(VIBRATOR_SERVICE) as Vibrator).vibrate(VibrationEffect.createOneShot(150, VibrationEffect.DEFAULT_AMPLITUDE)); MediaPlayer.create(this, android.provider.Settings.System.DEFAULT_NOTIFICATION_URI).start() } catch (_: Exception) {} }
    private fun shake() { /* Visual feedback */ }

    /** Saves a UPI ID → allocation mapping locally and pushes to Firestore. */
    private fun saveUpiAllocation(upiId: String, category: String) {
        if (upiId.isBlank()) return
        if (category.equals("no choice", ignoreCase = true)) {
            getSharedPreferences("UpiAllocationPrefs", MODE_PRIVATE)
                .edit().remove("ALLOC_$upiId").apply()
        } else {
            getSharedPreferences("UpiAllocationPrefs", MODE_PRIVATE)
                .edit().putString("ALLOC_$upiId", category).apply()
        }
        FirestoreSyncManager.pushAllDataToCloud(this)
    }


    private fun createShortcut() {
        val isXiaomi = "xiaomi".equals(android.os.Build.MANUFACTURER, ignoreCase = true) ||
                "poco".equals(android.os.Build.MANUFACTURER, ignoreCase = true) ||
                "redmi".equals(android.os.Build.MANUFACTURER, ignoreCase = true)

        if (isXiaomi && !isMiuiBackgroundStartActivityAllowed(this)) {
            androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("Xiaomi/POCO Device Detected")
                .setMessage("To ensure the Scanner Widget and background popups work perfectly, please enable 'Display pop-up windows while running in the background' in App Permissions.")
                .setPositiveButton("Go to Settings") { _, _ ->
                    try {
                        val intent = android.content.Intent("miui.intent.action.APP_PERM_EDITOR")
                        intent.setClassName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
                        intent.putExtra("extra_pkgname", packageName)
                        startActivity(intent)
                    } catch (e: Exception) {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        intent.data = android.net.Uri.parse("package:$packageName")
                        startActivity(intent)
                    }
                    triggerPinWidget()
                }
                .setNegativeButton("Later", null)
                .show()
        } else {
            triggerPinWidget()
        }
    }

    private fun isMiuiBackgroundStartActivityAllowed(context: android.content.Context): Boolean {
        return try {
            val ops = context.getSystemService(android.content.Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val method = ops.javaClass.getMethod(
                "checkOpNoThrow",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java
            )
            val mode = method.invoke(ops, 10021, android.os.Process.myUid(), context.packageName) as Int
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    private fun triggerPinWidget() {
        val appWidgetManager = getSystemService(android.appwidget.AppWidgetManager::class.java)
        val myProvider = android.content.ComponentName(this, ScannerWidget::class.java)

        if (appWidgetManager.isRequestPinAppWidgetSupported) {
            val intent = android.content.Intent(this, ScannerWidgetPinReceiver::class.java)
            val successCallback = android.app.PendingIntent.getBroadcast(
                this, 0, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_MUTABLE
            )
            val success = appWidgetManager.requestPinAppWidget(myProvider, null, successCallback)
            if (!success) {
                ToastHelper.showToast(this, "Your launcher doesn't support adding widgets from here")
            }
        } else {
            ToastHelper.showToast(this, "Widget pinning not supported by your launcher")
        }
    }
}
