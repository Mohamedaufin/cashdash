package com.cash.dash

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class PaymentNotificationService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {

        val text = sbn.notification.extras.get("android.text")?.toString()?.lowercase() ?: ""
        val pack = sbn.packageName.lowercase()

        // If GPay/PhonePe/Paytm or bank notification contains payment keywords
        if (pack.contains("gpay") || pack.contains("phonepe") || pack.contains("paytm") ||
            text.contains("debited") || text.contains("transaction successful") ||
            text.contains("upi") && text.contains("success")) {

            PaymentHandler.onPaymentDetected(this, text)
        }
    }
}
