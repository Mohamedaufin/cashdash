package com.cash.dash

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity

class CheckAppsActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        checkForGooglePayPackage()
    }

    private fun checkForGooglePayPackage() {
        val apps = packageManager.getInstalledPackages(0)

        for (app in apps) {
            if (app.packageName.contains("google", true) ||
                app.packageName.contains("pay", true)
            ) {
                Log.d("PAY-APPS", "FOUND → ${app.packageName}")
            }
        }

        // To finish automatically after listing packages
        finish()
    }
}
