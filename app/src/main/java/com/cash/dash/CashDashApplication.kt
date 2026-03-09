package com.cash.dash

import android.app.Application

class CashDashApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // Start Security Monitoring globally
        SecurityManager.startListening(this)
    }
}
