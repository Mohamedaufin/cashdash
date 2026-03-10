package com.cash.dash

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.fragment.app.Fragment
import com.google.android.material.snackbar.Snackbar
import java.util.*

class HomeFragment : Fragment() {

    private val PREFS = "AppPrefs"
    private val KEY_NAME = "user_name"
    private val PREFS_WALLET = "WalletPrefs"
    private val KEY_BALANCE = "wallet_balance"
    private val PREFS_SCHEDULE = "MoneySchedulePrefs"
    private val KEY_NEXT_DATE = "next_date"
    private val KEY_FREQUENCY = "frequency"

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_home, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        loadUserName(view)
        loadBalance(view)
        updateNextMoneyDays(view)

        view.findViewById<ImageView>(R.id.iconScanner).setOnClickListener {
            startActivity(Intent(requireContext(), ScannerActivity::class.java))
        }
        
        view.findViewById<ImageView>(R.id.btnMenu).setOnClickListener {
            startActivity(Intent(requireContext(), MenuActivity::class.java))
        }

        view.findViewById<ImageView>(R.id.btnProfile).setOnClickListener {
            startActivity(Intent(requireContext(), ProfileActivity::class.java))
        }
        
        view.findViewById<ImageView>(R.id.iconRigorTracker).setOnClickListener {
            startActivity(Intent(requireContext(), RigorActivity::class.java))
        }
    }

    fun refreshUI() {
        view?.let {
            loadUserName(it)
            loadBalance(it)
            updateNextMoneyDays(it)
        }
    }

    private fun loadUserName(view: View) {
        val prefs = requireContext().getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE)
        val name = prefs.getString(KEY_NAME, "User")
        view.findViewById<TextView>(R.id.tvGreeting)?.text = "Hello $name,"
    }

    private fun loadBalance(view: View) {
        val prefs = requireContext().getSharedPreferences(PREFS_WALLET, android.content.Context.MODE_PRIVATE)
        val bal = prefs.getInt(KEY_BALANCE, 0)
        val initialRaw = prefs.getInt("initial_balance", -1)
        
        val initial = if (initialRaw == -1) 0 else initialRaw
        val displayInitial = if (initial == 0 && bal == 0) 0 else initial.coerceAtLeast(1)
        
        view.findViewById<TextView>(R.id.tvBalance)?.text = "₹$bal/$displayInitial"
        
        val progressPercent = if (displayInitial > 0) ((bal.toFloat() / displayInitial.toFloat()) * 100).toInt().coerceIn(0, 100) else 0
        view.findViewById<com.cash.dash.GradientCircularProgressView>(R.id.walletProgress)?.setProgressCompat(progressPercent, true)
    }

    private fun updateNextMoneyDays(view: View) {
        val prefs = requireContext().getSharedPreferences(PREFS_SCHEDULE, android.content.Context.MODE_PRIVATE)
        val nextDate = prefs.getLong(KEY_NEXT_DATE, -1)
        val freq = prefs.getInt(KEY_FREQUENCY, -1)
        val textView = view.findViewById<TextView>(R.id.tvNextMoney) ?: return

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
            // Reset logic moved to Fragment but typically triggered by sync or activity
            // For now keep it as status display
            textView.text = "This money is tentatively till $nextDateStr"
        } else {
            textView.text = "This money is tentatively till $nextDateStr"
        }
    }
}
