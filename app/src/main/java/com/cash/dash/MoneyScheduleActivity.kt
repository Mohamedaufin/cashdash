package com.cash.dash

import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import java.util.*

class MoneyScheduleActivity : AppCompatActivity() {

    private val PREFS = "MoneySchedulePrefs"
    private val KEY_FREQUENCY = "frequency"
    private val KEY_NEXT_DATE = "next_date"

    private var selectedDateMillis: Long = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_moneyschedule)

        // 🔥 Make status bar same as MainActivity (transparent immersive)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)

        window.statusBarColor = Color.TRANSPARENT

        val rgFrequency = findViewById<RadioGroup>(R.id.rgFrequency)
        val calendarView = findViewById<CalendarView>(R.id.calendarView)
        val btnSave = findViewById<Button>(R.id.btnSaveSchedule)

        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)

        // -------------------------------------------
        // 1️⃣ Load existing saved frequency + date
        // -------------------------------------------
        val savedFrequency = prefs.getInt(KEY_FREQUENCY, -1)
        val savedDate = prefs.getLong(KEY_NEXT_DATE, -1)

        // Pre-select frequency radio button
        when (savedFrequency) {
            30 -> rgFrequency.check(R.id.rbMonthly)
            7 -> rgFrequency.check(R.id.rbWeekly)
            else -> if (savedFrequency > 0) {
                rgFrequency.check(R.id.rbCustom)
                val etCustomDays = findViewById<EditText>(R.id.etCustomDays)
                etCustomDays.visibility = View.VISIBLE
                etCustomDays.setText(savedFrequency.toString())
            }
        }

        // Pre-select previous date
        if (savedDate != -1L) {
            calendarView.date = savedDate
            selectedDateMillis = savedDate
        } else {
            selectedDateMillis = Calendar.getInstance().timeInMillis
        }

        // Handle custom radio
        val etCustomDays = findViewById<EditText>(R.id.etCustomDays)
        rgFrequency.setOnCheckedChangeListener { _, checkedId ->
            if (checkedId == R.id.rbCustom) {
                etCustomDays.visibility = View.VISIBLE
            } else {
                etCustomDays.visibility = View.GONE
            }
        }

        // -------------------------------------------
        // 2️⃣ Capture new date when user selects a new one
        // -------------------------------------------
        calendarView.setOnDateChangeListener { _, year, month, day ->
            val cal = Calendar.getInstance()
            cal.set(year, month, day)
            selectedDateMillis = cal.timeInMillis
        }

        // -------------------------------------------
        // 3️⃣ SAVE BUTTON
        // -------------------------------------------
        btnSave.setOnClickListener {

            // Validate frequency selection
            val freqId = rgFrequency.checkedRadioButtonId
            if (freqId == -1) {
                ToastHelper.showToast(this, "Select a frequency")
                return@setOnClickListener
            }

            // Validate date selection
            if (selectedDateMillis == -1L) {
                ToastHelper.showToast(this, "Select next receiving date")
                return@setOnClickListener
            }

            // Convert selected radio to days
            val frequencyDays = when (freqId) {
                R.id.rbMonthly -> 30
                R.id.rbWeekly -> 7
                R.id.rbCustom -> {
                    val customVal = etCustomDays.text.toString().toIntOrNull() ?: 0
                    if (customVal <= 0) {
                        ToastHelper.showToast(this@MoneyScheduleActivity, "Enter valid custom days")
                        return@setOnClickListener
                    }
                    customVal
                }
                else -> 30
            }

            // AUTO-ROLL FORWARD IF DATE HAS PASSED
            val today = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val next = Calendar.getInstance().apply {
                timeInMillis = selectedDateMillis
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            if (next.before(today)) {
                while (next.before(today)) {
                    next.add(Calendar.DAY_OF_YEAR, frequencyDays)
                }
                selectedDateMillis = next.timeInMillis
            }

            // SAVE NEW VALUES
            prefs.edit()
                .putInt(KEY_FREQUENCY, frequencyDays)
                .putLong(KEY_NEXT_DATE, selectedDateMillis)
                .putBoolean("cycle_initialized", true) // Ensure immediate rollover logic is active
                .apply()

            // Reset ALL category spent amounts for the new cycle (Fresh Start)
            val categoryPrefs = getSharedPreferences("CategoryPrefs", MODE_PRIVATE)
            val categories = categoryPrefs.getStringSet("categories", emptySet()) ?: emptySet()
            val graphPrefs = getSharedPreferences("GraphData", MODE_PRIVATE)
            val graphEditor = graphPrefs.edit()
            for (cat in categories) {
                graphEditor.putFloat("SPENT_$cat", 0f)
            }
            graphEditor.putFloat("SPENT_no choice", 0f)
            graphEditor.apply()

            // Replenish wallet balance to initial limit
            val wPrefs = getSharedPreferences("WalletPrefs", MODE_PRIVATE)
            val initialBal = wPrefs.getInt("initial_balance", 0)
            wPrefs.edit().putInt("wallet_balance", initialBal).apply()

            // Sync to Firestore
            FirestoreSyncManager.pushAllDataToCloud(this)

            ToastHelper.showToast(this, "Schedule updated & Cycle Reset!")

            finish()
        }
    }
}
