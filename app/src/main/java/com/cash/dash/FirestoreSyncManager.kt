package com.cash.dash

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.SetOptions
import com.google.firebase.firestore.FirebaseFirestore

import com.google.android.gms.tasks.Tasks
import com.google.firebase.firestore.ListenerRegistration
import android.content.Intent
import androidx.localbroadcastmanager.content.LocalBroadcastManager

object FirestoreSyncManager {

    const val ACTION_SYNC_UPDATE = "com.cash.dash.SYNC_UPDATE"
    private var listeners = mutableListOf<ListenerRegistration>()

    private const val TAG = "FirestoreSyncManager"

    // High level wrapper to blindly sync everything
    fun pushAllDataToCloud(context: Context) {
        val appContext = context.applicationContext
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val uid = user.uid

        Thread {
            try {
                val db = FirebaseFirestore.getInstance()

                val walletPrefs = appContext.getSharedPreferences("WalletPrefs", Context.MODE_PRIVATE)
                val categoryPrefs = appContext.getSharedPreferences("CategoryPrefs", Context.MODE_PRIVATE)
                val graphPrefs = appContext.getSharedPreferences("GraphData", Context.MODE_PRIVATE)
                val schedulePrefs = appContext.getSharedPreferences("MoneySchedulePrefs", Context.MODE_PRIVATE)
                val userPrefs = appContext.getSharedPreferences("AppPrefs", Context.MODE_PRIVATE)
                val categoryWeekPrefs = appContext.getSharedPreferences("CategoryWeekData", Context.MODE_PRIVATE)
                val scannerHistPrefs = appContext.getSharedPreferences("ScannerHistory", Context.MODE_PRIVATE)
                val localScanPrefs = appContext.getSharedPreferences("LocalScanPrefs", Context.MODE_PRIVATE)

                // 1. App Settings / User Config
                val userConfigData = hashMapOf(
                    "name" to (userPrefs.getString("user_name", "") ?: ""),
                    "email" to (userPrefs.getString("user_email", "") ?: ""),
                    "phone" to (userPrefs.getString("user_phone", "") ?: ""),
                    "password" to (userPrefs.getString("user_password", "") ?: ""),
                    "setup_complete" to !userPrefs.getBoolean("isFirstLaunch", true),
                    "wallet_popup_shown" to userPrefs.getBoolean("WalletPopupShown", false),
                    "account_creation_time" to userPrefs.getLong("account_creation_time", 0L),
                    "account_status" to "active"
                )
                db.collection("users").document(uid).collection("config").document("profile")
                    .set(userConfigData, SetOptions.merge())

                // 2. Wallet Data
                val initialBalance = walletPrefs.getInt("initial_balance", 0)
                val currentBalance = walletPrefs.getInt("wallet_balance", 0)
                val nextDateRaw = schedulePrefs.getLong("next_date", 0L)
                val formattedDate = if (nextDateRaw > 0) {
                    val sdf = java.text.SimpleDateFormat("dd/MM/yyyy", java.util.Locale.US)
                    sdf.format(java.util.Date(nextDateRaw))
                } else "not set"

                val walletData = hashMapOf(
                    "initial_balance" to initialBalance,
                    "current_balance" to currentBalance,
                    "next_date" to formattedDate,
                    "next_date_ms" to nextDateRaw,
                    "frequency" to schedulePrefs.getInt("frequency", 30),
                    "cycle_initialized" to schedulePrefs.getBoolean("cycle_initialized", false)
                )
                db.collection("users").document(uid).collection("config").document("wallet")
                    .set(walletData)

                // 3. Category Data (Limits & Spent)
                val categoriesSet = categoryPrefs.getStringSet("categories", emptySet()) ?: emptySet()
                val catMap = mutableMapOf<String, Any>()
                categoriesSet.forEach { catName ->
                    val limit = categoryPrefs.getInt("LIMIT_$catName", 0)
                    val spent = graphPrefs.getFloat("SPENT_$catName", 0f)
                    catMap[catName] = hashMapOf(
                        "limit" to limit,
                        "spent" to spent
                    )
                }
                db.collection("users").document(uid).collection("config").document("categories")
                    .set(hashMapOf(
                        "data" to catMap,
                        "allocation_categories" to categoriesSet.toList()
                    ))

                // 4. Transaction History
                val historySet = graphPrefs.getStringSet("HISTORY_LIST", emptySet()) ?: emptySet()
                val detailedTransactions = mutableListOf<Map<String, Any>>()

                historySet.forEach { entry ->
                    try {
                        val parts = entry.split("|")
                        if (parts.size >= 9) {
                            val itemMap = HashMap<String, Any>()
                            itemMap["type"] = parts[0]
                            itemMap["timestamp"] = parts[1]
                            itemMap["merchant"] = parts[2]
                            itemMap["category"] = parts[3]
                            itemMap["amount"] = parts[4].toIntOrNull() ?: 0
                            itemMap["week"] = parts[5].toIntOrNull() ?: 0
                            itemMap["day"] = parts[6].toIntOrNull() ?: 0
                            itemMap["month"] = parts[7].toIntOrNull() ?: 0
                            itemMap["year"] = parts[8].toIntOrNull() ?: 0
                            detailedTransactions.add(itemMap)
                        } else if (parts.size >= 5) {
                            val itemMap = HashMap<String, Any>()
                            itemMap["type"] = parts[0]
                            itemMap["timestamp"] = parts[1]
                            itemMap["merchant"] = parts[2]
                            itemMap["category"] = parts[3]
                            itemMap["amount"] = parts[4].toIntOrNull() ?: 0
                            detailedTransactions.add(itemMap)
                        }
                    } catch (e: Exception) {}
                }

                val historyPayload = HashMap<String, Any>()
                historyPayload["raw_list"] = historySet.toList()
                historyPayload["detailed_transactions"] = detailedTransactions

                db.collection("users").document(uid).collection("config").document("history")
                    .set(historyPayload)

                // 5. CategoryWeekData
                db.collection("users").document(uid).collection("config").document("analytics")
                    .set(hashMapOf("CategoryWeekData" to categoryWeekPrefs.all))

                // 6. ScannerHistory
                db.collection("users").document(uid).collection("config").document("history_scanner")
                    .set(hashMapOf("ScannerHistory" to scannerHistPrefs.all))

                // 7. LocalScanPrefs
                db.collection("users").document(uid).collection("config").document("undo_details")
                    .set(hashMapOf("LocalScanPrefs" to localScanPrefs.all))

                Log.d(TAG, "Background sync to cloud complete for user $uid")
            } catch (e: Exception) {
                Log.e(TAG, "Fatal error in background sync: ${e.message}")
            }
        }.start()
    }

    // Pull from Cloud -> Overwrite Local (Parallelized for Performance)
    fun pullDataFromCloud(context: Context, onComplete: (success: Boolean, profileExists: Boolean, isAdminDeleted: Boolean, profileData: Map<String, Any>?) -> Unit) {
        val user = FirebaseAuth.getInstance().currentUser
        if (user == null) {
            onComplete(false, false, false, null)
            return
        }

        val uid = user.uid
        val db = FirebaseFirestore.getInstance()
        val userDoc = db.collection("users").document(uid).collection("config")

        // 🚀 Parallelize all 7 document fetches
        val tProfile = userDoc.document("profile").get()
        val tWallet = userDoc.document("wallet").get()
        val tCategories = userDoc.document("categories").get()
        val tHistory = userDoc.document("history").get()
        val tAnalytics = userDoc.document("analytics").get()
        val tScanner = userDoc.document("history_scanner").get()
        val tUndo = userDoc.document("undo_details").get()

        Tasks.whenAllComplete(tProfile, tWallet, tCategories, tHistory, tAnalytics, tScanner, tUndo)
            .addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    Log.e(TAG, "Failed to pull cloud data: ${task.exception?.message}", task.exception)
                    onComplete(false, false, false, null)
                    return@addOnCompleteListener
                }

                val profileDoc = tProfile.result
                if (profileDoc == null || !profileDoc.exists()) {
                    onComplete(true, false, false, null) // Profile gone -> New user or just-deleted user (safe)
                    return@addOnCompleteListener
                }

                val status = profileDoc.getString("account_status") ?: "active"
                if (status == "admin_deleted") {
                    onComplete(true, true, true, null) // Explicitly banned by admin
                    return@addOnCompleteListener
                }

                val profileData = profileDoc.data

                // 1. Profile
                val userPrefs = context.getSharedPreferences("AppPrefs", Context.MODE_PRIVATE)
                val editor = userPrefs.edit()

                // Only clear if we are sure we want a full mirror,
                // but keep the current email/pass as they are definitely correct from the successful login.
                val currentEmail = userPrefs.getString("user_email", "")
                val currentPass = userPrefs.getString("user_password", "")

                editor.clear().apply()

                editor.putString("user_email", currentEmail)
                editor.putString("user_password", currentPass)

                profileDoc.getString("name")?.let { editor.putString("user_name", it) }
                profileDoc.getString("phone")?.let { editor.putString("user_phone", it) }
                profileDoc.getString("email")?.let { editor.putString("user_email", it) }
                profileDoc.getString("password")?.let { editor.putString("user_password", it) }

                val setupComplete = profileDoc.getBoolean("setup_complete") ?: false
                editor.putBoolean("isFirstLaunch", !setupComplete)

                profileDoc.getBoolean("wallet_popup_shown")?.let { editor.putBoolean("WalletPopupShown", it) }
                profileDoc.getLong("account_creation_time")?.let { editor.putLong("account_creation_time", it) }
                editor.apply()

                val walletDoc = tWallet.result
                if (walletDoc != null && walletDoc.exists()) {
                    val walletPrefs = context.getSharedPreferences("WalletPrefs", Context.MODE_PRIVATE)
                    val schedulePrefs = context.getSharedPreferences("MoneySchedulePrefs", Context.MODE_PRIVATE)

                    walletPrefs.edit().clear().apply() // Atomic Mirror
                    schedulePrefs.edit().clear().apply()

                    walletPrefs.edit()
                        .putInt("initial_balance", walletDoc.getLong("initial_balance")?.toInt() ?: 0)
                        .putInt("wallet_balance", walletDoc.getLong("current_balance")?.toInt() ?: 0)
                        .apply()
                    schedulePrefs.edit()
                        .putLong("next_date", walletDoc.getLong("next_date_ms") ?: 0L)
                        .putInt("frequency", walletDoc.getLong("frequency")?.toInt() ?: 30)
                        .putBoolean("cycle_initialized", walletDoc.getBoolean("cycle_initialized") ?: false)
                        .apply()
                }

                val catDoc = tCategories.result
                if (catDoc != null && catDoc.exists()) {
                    val catPrefs = context.getSharedPreferences("CategoryPrefs", Context.MODE_PRIVATE)
                    val graphPrefs = context.getSharedPreferences("GraphData", Context.MODE_PRIVATE)

                    catPrefs.edit().clear().apply() // Prevent ghost limits
                    // Note: We don't clear graphPrefs here yet as history needs it,
                    // we'll handle graphPrefs in the history block.

                    val cEdit = catPrefs.edit()
                    val gEdit = graphPrefs.edit()

                    val dataMap = catDoc.get("data") as? Map<String, Map<String, Any>>
                    if (dataMap != null) {
                        cEdit.putStringSet("categories", dataMap.keys)
                        for ((catName, valuesMap) in dataMap) {
                            val limit = (valuesMap["limit"] as? Number)?.toInt() ?: 0
                            val spent = (valuesMap["spent"] as? Number)?.toFloat() ?: 0f
                            cEdit.putInt("LIMIT_$catName", limit)
                            gEdit.putFloat("SPENT_$catName", spent)
                        }
                    }
                    cEdit.apply()
                    gEdit.apply()
                }

                val histDoc = tHistory.result
                if (histDoc != null && histDoc.exists()) {
                    val graphPrefs = context.getSharedPreferences("GraphData", Context.MODE_PRIVATE)

                    val detailed = histDoc.get("detailed_transactions") as? List<Map<String, Any>>
                    val rawList = histDoc.get("raw_list") as? List<String>

                    if (detailed != null || rawList != null) {
                        val gEdit = graphPrefs.edit()
                        val spentValues = mutableMapOf<String, Float>()
                        graphPrefs.all.forEach { (k, v) ->
                            if (k.startsWith("SPENT_") && v is Float) spentValues[k] = v
                        }
                        gEdit.clear().apply()

                        val gRestore = graphPrefs.edit()
                        spentValues.forEach { (k, v) -> gRestore.putFloat(k, v) }

                        val finalTransactions = mutableSetOf<String>()

                        if (detailed != null) {
                            for (map in detailed) {
                                val type = map["type"] as? String ?: "EXP"
                                val timestamp = map["timestamp"]?.toString() ?: "0"
                                val merchant = map["merchant"] as? String ?: "Unknown"
                                val category = map["category"] as? String ?: "no choice"
                                val amount = (map["amount"] as? Number)?.toFloat() ?: 0f

                                var hWeek = (map["week"] as? Number)?.toInt()
                                var hDay = (map["day"] as? Number)?.toInt()
                                var hMonth = (map["month"] as? Number)?.toInt()
                                var hYear = (map["year"] as? Number)?.toInt()

                                if (hWeek == null || hDay == null || hMonth == null || hYear == null) {
                                    val cal = java.util.Calendar.getInstance()
                                    try {
                                        cal.setFirstDayOfWeek(java.util.Calendar.MONDAY)
                                        cal.setMinimalDaysInFirstWeek(1)
                                        cal.timeInMillis = timestamp.toLong()
                                        hWeek = cal.get(java.util.Calendar.WEEK_OF_MONTH) - 1
                                        hDay = (cal.get(java.util.Calendar.DAY_OF_WEEK) + 5) % 7
                                        hMonth = cal.get(java.util.Calendar.MONTH)
                                        hYear = cal.get(java.util.Calendar.YEAR)
                                    } catch (e: Exception) {
                                        hWeek = 0; hDay = 0; hMonth = 0; hYear = 0
                                    }
                                }

                                val entryStr = "$type|$timestamp|$merchant|$category|${amount.toInt()}|$hWeek|$hDay|$hMonth|$hYear"
                                finalTransactions.add(entryStr)

                                val dayKey = "DAY_${hWeek}_${hDay}_${hMonth}_${hYear}"
                                val weekKey = "WEEK_${hWeek}_${hMonth}_${hYear}"
                                val monthKey = "MONTH_${hMonth}_${hYear}"

                                gRestore.putFloat(dayKey, graphPrefs.getFloat(dayKey, 0f) + amount)
                                gRestore.putFloat(weekKey, graphPrefs.getFloat(weekKey, 0f) + amount)
                                gRestore.putFloat(monthKey, graphPrefs.getFloat(monthKey, 0f) + amount)

                                gRestore.putString("TRANS_${timestamp}_TITLE", merchant)
                                gRestore.putString("TRANS_${timestamp}_CATEGORY", category)
                                gRestore.putInt("TRANS_${timestamp}_AMOUNT", amount.toInt())
                                gRestore.putInt("TRANS_${timestamp}_WEEK", hWeek)
                                gRestore.putInt("TRANS_${timestamp}_DAY", hDay)
                                gRestore.putInt("TRANS_${timestamp}_MONTH", hMonth)
                                gRestore.putInt("TRANS_${timestamp}_YEAR", hYear)
                            }
                        } else if (rawList != null) {
                            finalTransactions.addAll(rawList)
                            for (entry in rawList) {
                                val p = entry.split("|")
                                if (p.size >= 9) {
                                    val amount = p[4].toFloatOrNull() ?: 0f
                                    val hWeek = p[5].toIntOrNull() ?: 0
                                    val hDay = p[6].toIntOrNull() ?: 0
                                    val hMonth = p[7].toIntOrNull() ?: 0
                                    val hYear = p[8].toIntOrNull() ?: 0

                                    val dayKey = "DAY_${hWeek}_${hDay}_${hMonth}_${hYear}"
                                    val weekKey = "WEEK_${hWeek}_${hMonth}_${hYear}"
                                    val monthKey = "MONTH_${hMonth}_${hYear}"

                                    gRestore.putFloat(dayKey, graphPrefs.getFloat(dayKey, 0f) + amount)
                                    gRestore.putFloat(weekKey, graphPrefs.getFloat(weekKey, 0f) + amount)
                                    gRestore.putFloat(monthKey, graphPrefs.getFloat(monthKey, 0f) + amount)

                                    val timestamp = p[1]
                                    gRestore.putString("TRANS_${timestamp}_TITLE", p[2])
                                    gRestore.putString("TRANS_${timestamp}_CATEGORY", p[3])
                                    gRestore.putInt("TRANS_${timestamp}_AMOUNT", amount.toInt())
                                    gRestore.putInt("TRANS_${timestamp}_WEEK", hWeek)
                                    gRestore.putInt("TRANS_${timestamp}_DAY", hDay)
                                    gRestore.putInt("TRANS_${timestamp}_MONTH", hMonth)
                                    gRestore.putInt("TRANS_${timestamp}_YEAR", hYear)
                                }
                            }
                        }
                        gRestore.putStringSet("HISTORY_LIST", finalTransactions)
                        gRestore.apply()
                    }
                }

                val analyticsDoc = tAnalytics.result
                if (analyticsDoc != null && analyticsDoc.exists()) {
                    val cwdMap = analyticsDoc.get("CategoryWeekData") as? Map<String, Any>
                    if (cwdMap != null) {
                        val edit = context.getSharedPreferences("CategoryWeekData", Context.MODE_PRIVATE).edit()
                        edit.clear().apply() // Clean Mirror
                        for ((k, v) in cwdMap) {
                            if (v is Number) edit.putInt(k, v.toInt())
                        }
                        edit.apply()
                    }
                }

                val scannerDoc = tScanner.result
                if (scannerDoc != null && scannerDoc.exists()) {
                    val scanMap = scannerDoc.get("ScannerHistory") as? Map<String, Any>
                    if (scanMap != null) {
                        val edit = context.getSharedPreferences("ScannerHistory", Context.MODE_PRIVATE).edit()
                        edit.clear().apply() // Clean start
                        for ((k, v) in scanMap) {
                            if (v is Number) edit.putInt(k, v.toInt())
                            else if (v is String) edit.putString(k, v)
                            else if (v is Boolean) edit.putBoolean(k, v)
                        }
                        edit.apply()
                    }
                }

                val undoDoc = tUndo.result
                if (undoDoc != null && undoDoc.exists()) {
                    val undoMap = undoDoc.get("LocalScanPrefs") as? Map<String, Any>
                    if (undoMap != null) {
                        val edit = context.getSharedPreferences("LocalScanPrefs", Context.MODE_PRIVATE).edit()
                        edit.clear().apply() // Clean start
                        for ((k, v) in undoMap) {
                            if (v is String) edit.putString(k, v)
                        }
                        edit.apply()
                    }
                }

                Log.d(TAG, "Parallel pull from cloud complete for user $uid")
                onComplete(true, true, false, profileData)
            }
    }

    fun startRealTimeSync(context: Context) {
        val user = FirebaseAuth.getInstance().currentUser ?: return
        if (listeners.isNotEmpty()) return // Already listening

        val db = FirebaseFirestore.getInstance()
        val userDoc = db.collection("users").document(user.uid).collection("config")
        val appContext = context.applicationContext

        // 1. Profile Listener
        listeners.add(userDoc.document("profile").addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener
            val prefs = appContext.getSharedPreferences("AppPrefs", Context.MODE_PRIVATE)
            val editor = prefs.edit()
            snapshot.getString("name")?.let { editor.putString("user_name", it) }
            snapshot.getString("phone")?.let { editor.putString("user_phone", it) }
            snapshot.getString("email")?.let { editor.putString("user_email", it) }
            snapshot.getString("password")?.let { editor.putString("user_password", it) }
            snapshot.getBoolean("setup_complete")?.let { editor.putBoolean("isFirstLaunch", !it) }
            editor.apply()
            notifyUI(appContext)
        })

        // 2. Wallet & Schedule Listener
        listeners.add(userDoc.document("wallet").addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener
            val walletPrefs = appContext.getSharedPreferences("WalletPrefs", Context.MODE_PRIVATE)
            val schedulePrefs = appContext.getSharedPreferences("MoneySchedulePrefs", Context.MODE_PRIVATE)

            walletPrefs.edit()
                .putInt("initial_balance", snapshot.getLong("initial_balance")?.toInt() ?: 0)
                .putInt("wallet_balance", snapshot.getLong("current_balance")?.toInt() ?: 0)
                .apply()

            schedulePrefs.edit()
                .putLong("next_date", snapshot.getLong("next_date_ms") ?: 0L)
                .putInt("frequency", snapshot.getLong("frequency")?.toInt() ?: 30)
                .putBoolean("cycle_initialized", snapshot.getBoolean("cycle_initialized") ?: false)
                .apply()
            notifyUI(appContext)
        })

        // 3. Categories Listener
        listeners.add(userDoc.document("categories").addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener
            val catPrefs = appContext.getSharedPreferences("CategoryPrefs", Context.MODE_PRIVATE)
            val graphPrefs = appContext.getSharedPreferences("GraphData", Context.MODE_PRIVATE)
            val cEdit = catPrefs.edit()
            val gEdit = graphPrefs.edit()

            val dataMap = snapshot.get("data") as? Map<String, Map<String, Any>>
            if (dataMap != null) {
                cEdit.putStringSet("categories", dataMap.keys)
                for ((catName, valuesMap) in dataMap) {
                    cEdit.putInt("LIMIT_$catName", (valuesMap["limit"] as? Number)?.toInt() ?: 0)
                    gEdit.putFloat("SPENT_$catName", (valuesMap["spent"] as? Number)?.toFloat() ?: 0f)
                }
            }
            cEdit.apply()
            gEdit.apply()
            notifyUI(appContext)
        })

        // 4. History Listener
        listeners.add(userDoc.document("history").addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener
            val graphPrefs = appContext.getSharedPreferences("GraphData", Context.MODE_PRIVATE)

            val detailed = snapshot.get("detailed_transactions") as? List<Map<String, Any>>
            val rawList = snapshot.get("raw_list") as? List<String>

            if (detailed == null && rawList == null) return@addSnapshotListener

            // Rebuild summary keys logic
            val gEdit = graphPrefs.edit()
            val spentValues = mutableMapOf<String, Float>()
            graphPrefs.all.forEach { (k, v) -> if (k.startsWith("SPENT_") && v is Float) spentValues[k] = v }
            gEdit.clear().apply()

            val gRestore = graphPrefs.edit()
            spentValues.forEach { (k, v) -> gRestore.putFloat(k, v) }

            val finalTransactions = mutableSetOf<String>()

            if (detailed != null) {
                for (map in detailed) {
                    val type = map["type"] as? String ?: "EXP"
                    val timestamp = map["timestamp"]?.toString() ?: "0"
                    val merchant = map["merchant"] as? String ?: "Unknown"
                    val category = map["category"] as? String ?: "no choice"
                    val amount = (map["amount"] as? Number)?.toFloat() ?: 0f

                    var hWeek = (map["week"] as? Number)?.toInt()
                    var hDay = (map["day"] as? Number)?.toInt()
                    var hMonth = (map["month"] as? Number)?.toInt()
                    var hYear = (map["year"] as? Number)?.toInt()

                    // If indices are missing (older cloud data), compute from timestamp
                    if (hWeek == null || hDay == null || hMonth == null || hYear == null) {
                        val cal = java.util.Calendar.getInstance()
                        try {
                            cal.setFirstDayOfWeek(java.util.Calendar.MONDAY)
                            cal.setMinimalDaysInFirstWeek(1)
                            cal.timeInMillis = timestamp.toLong()
                            hWeek = cal.get(java.util.Calendar.WEEK_OF_MONTH) - 1
                            hDay = (cal.get(java.util.Calendar.DAY_OF_WEEK) + 5) % 7
                            hMonth = cal.get(java.util.Calendar.MONTH)
                            hYear = cal.get(java.util.Calendar.YEAR)
                        } catch (e: Exception) {
                            hWeek = 0; hDay = 0; hMonth = 0; hYear = 0
                        }
                    }

                    val entryStr = "$type|$timestamp|$merchant|$category|${amount.toInt()}|$hWeek|$hDay|$hMonth|$hYear"
                    finalTransactions.add(entryStr)

                    val dayKey = "DAY_${hWeek}_${hDay}_${hMonth}_${hYear}"
                    val weekKey = "WEEK_${hWeek}_${hMonth}_${hYear}"
                    val monthKey = "MONTH_${hMonth}_${hYear}"

                    gRestore.putFloat(dayKey, graphPrefs.getFloat(dayKey, 0f) + amount)
                    gRestore.putFloat(weekKey, graphPrefs.getFloat(weekKey, 0f) + amount)
                    gRestore.putFloat(monthKey, graphPrefs.getFloat(monthKey, 0f) + amount)

                    gRestore.putString("TRANS_${timestamp}_TITLE", merchant)
                    gRestore.putString("TRANS_${timestamp}_CATEGORY", category)
                    gRestore.putInt("TRANS_${timestamp}_AMOUNT", amount.toInt())
                    gRestore.putInt("TRANS_${timestamp}_WEEK", hWeek)
                    gRestore.putInt("TRANS_${timestamp}_DAY", hDay)
                    gRestore.putInt("TRANS_${timestamp}_MONTH", hMonth)
                    gRestore.putInt("TRANS_${timestamp}_YEAR", hYear)
                }
            } else if (rawList != null) {
                finalTransactions.addAll(rawList)
                for (entry in rawList) {
                    val p = entry.split("|")
                    if (p.size >= 9) {
                        val amount = p[4].toFloatOrNull() ?: 0f
                        val hWeek = p[5].toIntOrNull() ?: 0
                        val hDay = p[6].toIntOrNull() ?: 0
                        val hMonth = p[7].toIntOrNull() ?: 0
                        val hYear = p[8].toIntOrNull() ?: 0

                        val dayKey = "DAY_${hWeek}_${hDay}_${hMonth}_${hYear}"
                        val weekKey = "WEEK_${hWeek}_${hMonth}_${hYear}"
                        val monthKey = "MONTH_${hMonth}_${hYear}"

                        gRestore.putFloat(dayKey, graphPrefs.getFloat(dayKey, 0f) + amount)
                        gRestore.putFloat(weekKey, graphPrefs.getFloat(weekKey, 0f) + amount)
                        gRestore.putFloat(monthKey, graphPrefs.getFloat(monthKey, 0f) + amount)

                        val timestamp = p[1]
                        gRestore.putString("TRANS_${timestamp}_TITLE", p[2])
                        gRestore.putString("TRANS_${timestamp}_CATEGORY", p[3])
                        gRestore.putInt("TRANS_${timestamp}_AMOUNT", amount.toInt())
                        gRestore.putInt("TRANS_${timestamp}_WEEK", hWeek)
                        gRestore.putInt("TRANS_${timestamp}_DAY", hDay)
                        gRestore.putInt("TRANS_${timestamp}_MONTH", hMonth)
                        gRestore.putInt("TRANS_${timestamp}_YEAR", hYear)
                    }
                }
            }

            gRestore.putStringSet("HISTORY_LIST", finalTransactions)
            gRestore.apply()
            notifyUI(appContext)
        })

        // 5. Analytics Listener
        listeners.add(userDoc.document("analytics").addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener
            xmlMapToPrefs(appContext, "CategoryWeekData", snapshot.get("CategoryWeekData") as? Map<String, Any>)
            notifyUI(appContext)
        })

        // 6. Scanner & Undo Listeners
        listeners.add(userDoc.document("history_scanner").addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener
            xmlMapToPrefs(appContext, "ScannerHistory", snapshot.get("ScannerHistory") as? Map<String, Any>)
            notifyUI(appContext)
        })
        listeners.add(userDoc.document("undo_details").addSnapshotListener { snapshot, e ->
            if (e != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener
            xmlMapToPrefs(appContext, "LocalScanPrefs", snapshot.get("LocalScanPrefs") as? Map<String, Any>)
            notifyUI(appContext)
        })
    }

    private fun xmlMapToPrefs(context: Context, prefName: String, map: Map<String, Any>?) {
        if (map == null) return
        val edit = context.getSharedPreferences(prefName, Context.MODE_PRIVATE).edit()
        edit.clear().apply()
        for ((k, v) in map) {
            when (v) {
                is Number -> edit.putInt(k, v.toInt())
                is String -> edit.putString(k, v)
                is Boolean -> edit.putBoolean(k, v)
            }
        }
        edit.apply()
    }

    private fun notifyUI(context: Context) {
        LocalBroadcastManager.getInstance(context).sendBroadcast(Intent(ACTION_SYNC_UPDATE))
    }

    fun stopRealTimeSync() {
        listeners.forEach { it.remove() }
        listeners.clear()
    }
}
