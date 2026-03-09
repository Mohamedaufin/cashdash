package com.aufin.cashdash

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.aufin.cashdash/payment_channel"
    private var methodChannel: MethodChannel? = null
    
    // Hold pending result if Flutter isn't ready when the intent arrives
    private var pendingPaymentResult: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "checkPendingPaymentResult") {
                if (pendingPaymentResult != null) {
                    result.success(pendingPaymentResult)
                    pendingPaymentResult = null
                } else {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("payment_detected", false) == true) {
            val resultText = intent.getStringExtra("result") ?: "✔ Transaction Successful"
            if (methodChannel != null) {
                methodChannel?.invokeMethod("onPaymentDetected", resultText)
            } else {
                pendingPaymentResult = resultText
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "UPI SMS Channel"
            val descriptionText = "Notifications for UPI Payments"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel("upi_sms_channel", name, importance).apply {
                description = descriptionText
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}
