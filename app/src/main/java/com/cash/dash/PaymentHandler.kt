package com.cash.dash

import android.content.Context
import android.content.Intent

object PaymentHandler {

    fun onPaymentDetected(context: Context, details:String){

        // You can later extract amount, ref number here.
        // For now just show popup screen.

        val i = Intent(context, SuccessActivity::class.java).apply {
            putExtra("info", details)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(i)
    }
}
