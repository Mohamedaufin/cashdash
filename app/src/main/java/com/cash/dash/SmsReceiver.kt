package com.cash.dash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {

        if(intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val fullText = messages.joinToString("") { it.messageBody }.lowercase()

        // 🔥 SIMPLE UPI PAYMENT DETECTION
        if ("upi" in fullText && ("debited" in fullText || "credited" in fullText)) {

            ToastHelper.showToast(context, "✔ Transaction Successful", Toast.LENGTH_LONG)

            // Return → MainActivity
            val i = Intent(context, MainActivity::class.java)
            i.putExtra("payment_status", "success") // Use same key as ScannerActivity for consistency
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            context.startActivity(i)
        }
    }
}
