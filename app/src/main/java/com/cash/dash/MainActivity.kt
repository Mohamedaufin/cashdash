package com.cash.dash

import android.content.Intent
import android.os.Bundle
import android.graphics.Color
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.snackbar.Snackbar
import java.util.*

class MainActivity : AppCompatActivity() {

    private val PREFS = "AppPrefs"
    private val KEY_NAME = "user_name"
    private val PREFS_WALLET = "WalletPrefs"
    private val KEY_BALANCE = "wallet_balance"

    private val PREFS_SCHEDULE = "MoneySchedulePrefs"
    private val KEY_NEXT_DATE = "next_date"
    private val KEY_FREQUENCY = "frequency"

    private val syncReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            loadUserName()
            loadBalance()
            updateNextMoneyDays()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT

        loadUserName()
        loadBalance()
        updateNextMoneyDays()
        ensureAccountCreationTime()

        findViewById<ImageView>(R.id.iconScanner).setOnClickListener {
            startActivity(Intent(this, ScannerActivity::class.java))
        }
        findViewById<LinearLayout>(R.id.tabAllocator).setOnClickListener {
            startActivity(Intent(this, AllocatorActivity::class.java))
            overridePendingTransition(R.anim.slide_in_left, R.anim.slide_out_right)
        }
        findViewById<ImageView>(R.id.btnMenu).setOnClickListener {
            startActivity(Intent(this, MenuActivity::class.java))
        }

        findViewById<ImageView>(R.id.btnProfile).setOnClickListener {
            startActivity(Intent(this, ProfileActivity::class.java))
        }
        findViewById<ImageView>(R.id.iconRigorTracker).setOnClickListener {
            startActivity(Intent(this, RigorActivity::class.java))
        }

        // NEW ➜ History tab opens HistoryActivity
        findViewById<LinearLayout>(R.id.tabHistory)?.setOnClickListener {
            startActivity(Intent(this, HistoryActivity::class.java))
            overridePendingTransition(R.anim.slide_in_right, R.anim.slide_out_left)
        }

        // 🔥 Intercept Background Push Notifications
        // When FCM is tapped from the background, Android auto-launches MainActivity.
        // If it contains "google.message_id" in extras, we know it was a push!
        if (intent.extras?.containsKey("google.message_id") == true) {
            val notifIntent = Intent(this, NotificationActivity::class.java)
            startActivity(notifIntent)
        }

        SecurityManager.startListening(this)
        requestNotificationPermission()
        registerFCMToken()
        
        FirestoreSyncManager.startRealTimeSync(this)
    }

    override fun onStart() {
        super.onStart()
        LocalBroadcastManager.getInstance(this).registerReceiver(
            syncReceiver, IntentFilter(FirestoreSyncManager.ACTION_SYNC_UPDATE)
        )
    }

    override fun onStop() {
        super.onStop()
        LocalBroadcastManager.getInstance(this).unregisterReceiver(syncReceiver)
    }

    private fun requestNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (androidx.core.content.ContextCompat.checkSelfPermission(
                    this, android.Manifest.permission.POST_NOTIFICATIONS
                ) != android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                androidx.core.app.ActivityCompat.requestPermissions(
                    this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101
                )
            }
        }
    }

    private fun registerFCMToken() {
        val user = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser ?: return
        com.google.firebase.messaging.FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val token = task.result
                if (token != null) {
                    val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    db.collection("users").document(user.uid)
                        .set(hashMapOf("fcmToken" to token), com.google.firebase.firestore.SetOptions.merge())
                }
            }
        }
    }

    private fun ensureAccountCreationTime() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (!prefs.contains("account_creation_time")) {
            prefs.edit().putLong("account_creation_time", System.currentTimeMillis()).apply()
            // Force a sync to cloud immediately so this baseline exists across devices
            FirestoreSyncManager.pushAllDataToCloud(this)
        }
    }


    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Update with new intent extras
    }

    override fun onResume() {
        super.onResume()

        loadUserName()
        loadBalance()
        updateNextMoneyDays()

        val result = intent.getStringExtra("payment_status")

        when (result) {
            "success" -> Snackbar.make(
                findViewById(android.R.id.content),
                "✔ Payment Successful",
                Snackbar.LENGTH_LONG
            ).show()

            "failed" -> Snackbar.make(
                findViewById(android.R.id.content),
                "❌ Payment Failed or Cancelled",
                Snackbar.LENGTH_LONG
            ).show()
        }

        intent.removeExtra("payment_status")
    }

    private fun loadUserName() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val name = prefs.getString(KEY_NAME, "User")
        findViewById<TextView>(R.id.tvGreeting)?.text = "Hello $name,"
    }

    private fun loadBalance() {
        val prefs = getSharedPreferences(PREFS_WALLET, MODE_PRIVATE)
        val bal = prefs.getInt(KEY_BALANCE, 0)
        val initialRaw = prefs.getInt("initial_balance", -1)
        
        // Fix for 0/0 display instead of 0/1
        val initial = if (initialRaw == -1) 0 else initialRaw
        val displayInitial = if (initial == 0 && bal == 0) 0 else initial.coerceAtLeast(1)
        
        findViewById<TextView>(R.id.tvBalance)?.text = "₹$bal/$displayInitial"
        
        // Update Circular Progress (100 is full)
        val progressPercent = if (displayInitial > 0) ((bal.toFloat() / displayInitial.toFloat()) * 100).toInt().coerceIn(0, 100) else 0
        findViewById<com.cash.dash.GradientCircularProgressView>(R.id.walletProgress)?.setProgressCompat(progressPercent, true)

        if (intent.getBooleanExtra("from_splash", false)) {
            intent.removeExtra("from_splash")
            val appPrefs = getSharedPreferences("AppPrefs", MODE_PRIVATE)
            
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (initialRaw == -1 && !appPrefs.getBoolean("WalletPopupShown", false)) {
                    showFirstTimeWalletPopup(appPrefs)
                }
            }, 1200) // Delay to let the zoom transition settle for first-time user
        }
    }

    private fun showFirstTimeWalletPopup(appPrefs: android.content.SharedPreferences) {
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            background = androidx.core.content.ContextCompat.getDrawable(context, R.drawable.bg_glass_3d)
            setPadding(70, 70, 70, 70)
            gravity = android.view.Gravity.CENTER
        }

        val title = android.widget.TextView(this).apply {
            text = "Update Wallet Balance"
            textSize = 22f
            setTypeface(null, android.graphics.Typeface.BOLD)
            setTextColor(android.graphics.Color.WHITE)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 40)
        }
        layout.addView(title)

        val btnSet = android.widget.Button(this).apply {
            text = "Set now"
            isAllCaps = false
            textSize = 16f
            setTextColor(android.graphics.Color.WHITE)
            background = androidx.core.content.ContextCompat.getDrawable(context, R.drawable.bg_glass_3d)
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, 
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        layout.addView(btnSet)

        val dialog = androidx.appcompat.app.AlertDialog.Builder(this)
            .setView(layout)
            .setCancelable(false)
            .create()
            
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        
        btnSet.setOnClickListener {
            dialog.dismiss()
            startActivity(android.content.Intent(this, BalanceSetupActivity::class.java))
        }

        dialog.show()
    }


    private fun updateNextMoneyDays() {
        val prefs = getSharedPreferences(PREFS_SCHEDULE, MODE_PRIVATE)

        val nextDate = prefs.getLong(KEY_NEXT_DATE, -1)
        val freq = prefs.getInt(KEY_FREQUENCY, -1)

        val textView = findViewById<TextView>(R.id.tvNextMoney) ?: return

        if (nextDate == -1L || freq == -1) {
            textView.text = "Next money: schedule not set"
            return
        }

        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val next = Calendar.getInstance().apply {
            timeInMillis = nextDate
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val nextDateStr = "%02d/%02d/%04d".format(
            next.get(Calendar.DAY_OF_MONTH),
            next.get(Calendar.MONTH) + 1,
            next.get(Calendar.YEAR)
        )

        if (today.after(next)) {
            val isAlreadyEstablished = prefs.getBoolean("cycle_initialized", false)
            while (next.before(today)) {
                next.add(Calendar.DAY_OF_YEAR, freq)
            }
            prefs.edit().putLong(KEY_NEXT_DATE, next.timeInMillis).apply()

            performManualCycleReset(textView, next, isAlreadyEstablished)
        } else {
            textView.text = "This money is tentatively till $nextDateStr"
        }
    }

    private fun performManualCycleReset(textView: TextView, nextIn: Calendar? = null, isEstablished: Boolean = true) {
        val prefs = getSharedPreferences(PREFS_SCHEDULE, MODE_PRIVATE)
        val freq = prefs.getInt(KEY_FREQUENCY, 7)
        
        val next = nextIn ?: Calendar.getInstance().apply {
            timeInMillis = prefs.getLong(KEY_NEXT_DATE, System.currentTimeMillis())
            add(Calendar.DAY_OF_YEAR, freq)
        }
        
        // 1. Replenish Wallet Balance
        val wPrefs = getSharedPreferences(PREFS_WALLET, MODE_PRIVATE)
        val initialBal = wPrefs.getInt("initial_balance", 0)
        wPrefs.edit().putInt(KEY_BALANCE, initialBal).apply()

        // 2. Reset ALL category spent amounts
        val categoryPrefs = getSharedPreferences("CategoryPrefs", MODE_PRIVATE)
        val categories = categoryPrefs.getStringSet("categories", emptySet()) ?: emptySet()
        val graphPrefs = getSharedPreferences("GraphData", MODE_PRIVATE)
        val graphEditor = graphPrefs.edit()
        for (cat in categories) {
            graphEditor.putFloat("SPENT_$cat", 0f)
        }
        graphEditor.putFloat("SPENT_no choice", 0f)
        graphEditor.apply()

        // 3. Mark initialized & Save next date (if manual trigger)
        if (nextIn == null) {
            prefs.edit()
                .putLong(KEY_NEXT_DATE, next.timeInMillis)
                .putBoolean("cycle_initialized", true)
                .apply()
        }

        // 4. Update UI
        val newDateStr = "%02d/%02d/%04d".format(
            next.get(Calendar.DAY_OF_MONTH),
            next.get(Calendar.MONTH) + 1,
            next.get(Calendar.YEAR)
        )
        textView.text = "This money is tentatively till $newDateStr"
        
        if (isEstablished) {
            ToastHelper.showToast(this, "Cycle Renewed! (Debug: Balance & Spent Reset)", Toast.LENGTH_LONG)
        }

        // 5. Sync to Cloud
        FirestoreSyncManager.pushAllDataToCloud(this)
    }

    private fun openGooglePay() {
        val pkg = "com.google.android.apps.nbu.paisa.user"
        val intent = packageManager.getLaunchIntentForPackage(pkg)

        if (intent != null) {
            startActivity(intent)
            Toast.makeText(this,"Tap Scan in Google Pay 🔍",Toast.LENGTH_SHORT).show()
        } else ToastHelper.showToast(this,"Google Pay not installed")
    }

    private fun openOtherUPIApps() {
        val detectIntent = Intent(Intent.ACTION_VIEW)
        detectIntent.data = android.net.Uri.parse("upi://pay")

        val upiApps = packageManager.queryIntentActivities(detectIntent, 0)

        if (upiApps.isEmpty()) {
            ToastHelper.showToast(this,"No UPI Apps Found")
            return
        }

        val chooser = Intent.createChooser(detectIntent,"Select UPI App")
        startActivity(chooser)
    }
}
