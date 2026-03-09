package com.aufin.cashdash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if(intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val fullText = messages.joinToString("") { it.messageBody }.lowercase()

        // SIMPLE UPI PAYMENT DETECTION
        if ("upi" in fullText && ("debited" in fullText || "credited" in fullText)) {
            
            // Return to MainActivity
            val i = Intent(context, MainActivity::class.java).apply {
                putExtra("result", "✔ Transaction Successful")
                putExtra("payment_detected", true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }

            val pendingIntent = android.app.PendingIntent.getActivity(
                context, 
                0, 
                i, 
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            // Make sure the notification channel is created in MainActivity
            val notification = NotificationCompat.Builder(context, "upi_sms_channel")
                .setSmallIcon(android.R.drawable.ic_dialog_info) // Using a default icon for simplicity
                .setContentTitle("Payment Detected")
                .setContentText("A new UPI transaction was detected.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()

            NotificationManagerCompat.from(context).notify(System.currentTimeMillis().toInt(), notification)
        }
    }
}
