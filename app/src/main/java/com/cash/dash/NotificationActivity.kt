package com.cash.dash

import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.FirebaseFirestore

import java.text.SimpleDateFormat
import java.util.*

class NotificationActivity : AppCompatActivity() {

    private var allDocs = listOf<com.google.firebase.firestore.DocumentSnapshot>()
    private var currentFilter = "all" // "all", "responded", "pending"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_notification)

        // Immersive UI
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT

        val btnBack = findViewById<ImageButton>(R.id.btnBack)
        btnBack.setOnClickListener { finish() }

        // Wire up filter chips
        val chipAll = findViewById<TextView>(R.id.chipAll)
        val chipResponded = findViewById<TextView>(R.id.chipResponded)
        val chipPending = findViewById<TextView>(R.id.chipPending)

        chipAll.setOnClickListener { setFilter("all") }
        chipResponded.setOnClickListener { setFilter("responded") }
        chipPending.setOnClickListener { setFilter("pending") }

        updateChipAppearance()

        markAllAsRead()
        loadNotifications()
    }

    private fun setFilter(filter: String) {
        currentFilter = filter
        updateChipAppearance()
        renderNotifications()
    }

    private fun updateChipAppearance() {
        val chipAll = findViewById<TextView>(R.id.chipAll)
        val chipResponded = findViewById<TextView>(R.id.chipResponded)
        val chipPending = findViewById<TextView>(R.id.chipPending)

        val activeColor = Color.WHITE
        val inactiveColor = Color.parseColor("#606880")

        chipAll.setTextColor(if (currentFilter == "all") activeColor else inactiveColor)
        chipResponded.setTextColor(if (currentFilter == "responded") activeColor else inactiveColor)
        chipPending.setTextColor(if (currentFilter == "pending") activeColor else inactiveColor)
    }

    private fun markAllAsRead() {
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val db = FirebaseFirestore.getInstance()
        
        // Fetch ALL unread notifications to clear 'ghost' items (those without timestamps)
        db.collection("users").document(user.uid).collection("notifications")
            .whereEqualTo("read", false)
            .get()
            .addOnSuccessListener { docs ->
                if (!docs.isEmpty) {
                    val batch = db.batch()
                    for (doc in docs) {
                        batch.update(doc.reference, "read", true)
                    }
                    batch.commit().addOnSuccessListener {
                        android.util.Log.d("NotificationActivity", "All notifications marked as read.")
                    }
                }
            }
    }

    private fun loadNotifications() {
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val db = FirebaseFirestore.getInstance()
        val tvEmpty = findViewById<TextView>(R.id.tvEmptyNotifications)

        db.collection("users").document(user.uid).collection("notifications")
            .orderBy("timestamp", Query.Direction.DESCENDING)
            .get()
            .addOnSuccessListener { docs ->
                if (docs.isEmpty) {
                    tvEmpty.visibility = View.VISIBLE
                    allDocs = emptyList()
                    renderNotifications()
                    return@addOnSuccessListener
                }

                tvEmpty.visibility = View.GONE
                
                val rawDocs = docs.documents
                
                // Silent background cleanup for legacy duplicates
                val groupedDocs = rawDocs.groupBy { 
                    val q = it.getString("query")?.trim() ?: ""
                    val s = it.getString("subject")?.trim() ?: ""
                    "$s|$q"
                }

                val docsToDelete = mutableListOf<com.google.firebase.firestore.DocumentSnapshot>()
                for (group in groupedDocs.values) {
                    if (group.size > 1) {
                        val respondedDoc = group.find { (it.getString("reply") ?: "Waiting for reply...") != "Waiting for reply..." }
                        val docToKeep = respondedDoc ?: group.maxByOrNull { it.getLong("timestamp") ?: 0L } ?: group.first()
                        for (d in group) {
                            if (d.id != docToKeep.id) docsToDelete.add(d)
                        }
                    }
                }

                if (docsToDelete.isNotEmpty()) {
                    val batch = db.batch()
                    for (d in docsToDelete) batch.delete(d.reference)
                    batch.commit()
                }

                // Cache cleaned docs list
                allDocs = rawDocs.filter { doc -> !docsToDelete.any { it.id == doc.id } }
                renderNotifications()
            }
    }

    private fun renderNotifications() {
        val listContainer = findViewById<LinearLayout>(R.id.notificationList)
        val tvEmpty = findViewById<TextView>(R.id.tvEmptyNotifications)
        val filterBar = findViewById<LinearLayout>(R.id.filterBar)
        val scrollView = findViewById<ScrollView>(R.id.scrollNotifications)
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val db = FirebaseFirestore.getInstance()
        listContainer.removeAllViews()

        val filteredDocs = when (currentFilter) {
            "responded" -> allDocs.filter { (it.getString("reply") ?: "Waiting for reply...") != "Waiting for reply..." }
            "pending"   -> allDocs.filter { (it.getString("reply") ?: "Waiting for reply...") == "Waiting for reply..." }
            else        -> allDocs
        }

        // 1. COMPLETELY EMPTY STATE (No notifications at all)
        if (allDocs.isEmpty()) {
            filterBar.visibility = View.GONE
            scrollView.visibility = View.GONE
            tvEmpty.text = "No notifications yet.\n\nWe'll notify you when your support\nqueries are resolved!"
            tvEmpty.visibility = View.VISIBLE
            return
        }

        // 2. FILTERED EMPTY STATE (Notifications exist, but none for this filter)
        if (filteredDocs.isEmpty()) {
            filterBar.visibility = View.VISIBLE
            scrollView.visibility = View.GONE
            tvEmpty.text = when (currentFilter) {
                "pending" -> "All your queries have been responded!"
                "responded" -> "No queries have been answered yet."
                else -> ""
            }
            tvEmpty.visibility = View.VISIBLE
            return
        }

        // 3. RESULTS STATE
        filterBar.visibility = View.VISIBLE
        scrollView.visibility = View.VISIBLE
        tvEmpty.visibility = View.GONE

                for (doc in filteredDocs) {
                    val view = layoutInflater.inflate(R.layout.item_notification, listContainer, false)
                    val tvQuery = view.findViewById<TextView>(R.id.tvNotificationQuery)
                    val tvReply = view.findViewById<TextView>(R.id.tvNotificationReply)
                    val tvTime = view.findViewById<TextView>(R.id.tvNotificationTime)
                    val tvTitle = view.findViewById<TextView>(R.id.tvNotificationTitle)
                    val viewAccentBar = view.findViewById<View>(R.id.viewAccentBar)

                    val queryText = doc.getString("query") ?: "No query"
                    val replyText = doc.getString("reply") ?: "Waiting for reply..."
                    val subjectText = doc.getString("subject") ?: "General Help"
                    val timestamp = doc.getLong("timestamp") ?: 0L

                    val queryFormatted = android.text.Html.fromHtml(
                        "<b>Subject:</b> $subjectText<br><br><b>Question:</b> $queryText",
                        android.text.Html.FROM_HTML_MODE_LEGACY
                    )
                    
                    if (replyText == "Waiting for reply...") {
                        tvTitle.text = "Waiting for response"
                        tvTitle.setTextColor(Color.parseColor("#FFD93D"))
                        viewAccentBar.setBackgroundColor(Color.parseColor("#FFD93D"))
                        tvQuery.text = queryFormatted
                        tvReply.visibility = View.GONE
                    } else {
                        tvTitle.text = "Query responded"
                        tvTitle.setTextColor(Color.parseColor("#4ADE80"))
                        viewAccentBar.setBackgroundColor(Color.parseColor("#4ADE80"))
                        tvQuery.text = queryFormatted
                        tvReply.visibility = View.VISIBLE
                        
                        val replyFormatted = android.text.Html.fromHtml(
                            "<font color='#4ADE80'><b>Response</b></font><br><br><font color='#E0EBF5'>$replyText</font>",
                            android.text.Html.FROM_HTML_MODE_LEGACY
                        )
                        tvReply.text = replyFormatted
                    }

                    if (timestamp > 0L) {
                        val sdf = java.text.SimpleDateFormat("dd MMM, hh:mm a", java.util.Locale.getDefault())
                        tvTime.text = sdf.format(java.util.Date(timestamp))
                    }

                    // -------------------------------------------------------------------
                    // 🟢 SWIPE TO DELETE (Right-to-Left)
                    // -------------------------------------------------------------------
                    val swipeDetector = android.view.GestureDetector(this@NotificationActivity, object : android.view.GestureDetector.SimpleOnGestureListener() {
                        override fun onFling(e1: android.view.MotionEvent?, e2: android.view.MotionEvent, vx: Float, vy: Float): Boolean {
                            if (e1 != null) {
                                val deltaX = e1.x - e2.x
                                val deltaY = e1.y - e2.y
                                if (Math.abs(deltaX) > Math.abs(deltaY) && deltaX > 80 && Math.abs(vx) > 50) {
                                    view.animate().translationX(-view.width.toFloat()).alpha(0f).setDuration(250)
                                        .withEndAction {
                                            val box = LinearLayout(this@NotificationActivity)
                                            box.orientation = LinearLayout.VERTICAL
                                            box.setPadding(60, 60, 60, 50)
                                            box.setBackgroundResource(R.drawable.bg_transaction)

                                            val titleView = TextView(this@NotificationActivity).apply {
                                                text = "Delete query?"
                                                textSize = 22f
                                                setTextColor(Color.WHITE)
                                                setTypeface(null, android.graphics.Typeface.BOLD)
                                                gravity = android.view.Gravity.CENTER
                                                setPadding(0, 0, 0, 20)
                                            }
                                            box.addView(titleView)

                                            val msgView = TextView(this@NotificationActivity).apply {
                                                text = "Remove this query from your history?"
                                                textSize = 16f
                                                setTextColor(Color.parseColor("#A0A0A0"))
                                                gravity = android.view.Gravity.CENTER
                                                setPadding(0, 0, 0, 50)
                                            }
                                            box.addView(msgView)

                                            val buttonContainer = LinearLayout(this@NotificationActivity).apply {
                                                orientation = LinearLayout.HORIZONTAL
                                                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                                            }

                                            val dialog = androidx.appcompat.app.AlertDialog.Builder(this@NotificationActivity)
                                                .setView(box)
                                                .setCancelable(false)
                                                .create()
                                            dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)

                                            val btnCancel = android.widget.Button(this@NotificationActivity).apply {
                                                text = "Cancel"
                                                isAllCaps = false
                                                setTextColor(Color.WHITE)
                                                background = androidx.core.content.ContextCompat.getDrawable(context, R.drawable.bg_glass_input)
                                                layoutParams = LinearLayout.LayoutParams(0, 140, 1f).apply {
                                                    setMargins(0, 0, 15, 0)
                                                }
                                                setOnClickListener {
                                                    view.animate().translationX(0f).alpha(1f).setDuration(200).start()
                                                    dialog.dismiss()
                                                }
                                            }
                                            buttonContainer.addView(btnCancel)

                                            val btnDelete = android.widget.Button(this@NotificationActivity).apply {
                                                text = "Delete"
                                                isAllCaps = false
                                                setTextColor(Color.WHITE)
                                                background = androidx.core.content.ContextCompat.getDrawable(context, R.drawable.bg_glass_input)
                                                layoutParams = LinearLayout.LayoutParams(0, 140, 1f).apply {
                                                    setMargins(15, 0, 0, 0)
                                                }
                                                setOnClickListener {
                                                    val queryToDelete = doc.getString("query") ?: "No query"
                                                    db.collection("users").document(user.uid).collection("notifications")
                                                        .whereEqualTo("query", queryToDelete)
                                                        .get()
                                                        .addOnSuccessListener { docsToDelete ->
                                                            val batch = db.batch()
                                                            for (d in docsToDelete) {
                                                                batch.delete(d.reference)
                                                            }
                                                            batch.commit().addOnSuccessListener {
                                                                ToastHelper.showToast(this@NotificationActivity, "Query deleted")
                                                                loadNotifications()
                                                                dialog.dismiss()
                                                            }
                                                        }
                                                }
                                            }
                                            buttonContainer.addView(btnDelete)
                                            box.addView(buttonContainer)
                                            dialog.show()
                                        }.start()
                                    return true
                                }
                            }
                            return false
                        }
                    })

                    view.isClickable = true
                    view.isFocusable = true
                    view.setOnClickListener { /* Required for touch events to flow */ }

                    var startX = 0f
                    var startY = 0f
                    var isSwiping = false

                    view.setOnTouchListener { v, event ->
                        var isHandled = false
                        when (event.action) {
                            android.view.MotionEvent.ACTION_DOWN -> {
                                startX = event.x
                                startY = event.y
                                isSwiping = false
                                isHandled = true // Vital for capturing MOVE later
                            }
                            android.view.MotionEvent.ACTION_MOVE -> {
                                val dX = Math.abs(event.x - startX)
                                val dY = Math.abs(event.y - startY)
                                if (dX > dY && dX > 15) {
                                    isSwiping = true
                                    v.parent.requestDisallowInterceptTouchEvent(true)
                                }
                            }
                            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                                if (isSwiping) isHandled = true
                            }
                        }
                        val detectorHandled = swipeDetector.onTouchEvent(event)
                        isHandled || detectorHandled
                    }

                    // Optional: ensure children don't eat touches if they are clickable
                    tvQuery.isClickable = false
                    tvReply.isClickable = false

                    listContainer.addView(view)

                    // -------------------------------------------------------------------
                    // 🟢 HIGHLIGHT RECENTLY READ REPLIES
                    // -------------------------------------------------------------------
                    val isUnreadLocally = doc.getBoolean("read") == false
                    val hasReply = replyText != "Waiting for reply..." && replyText.isNotEmpty()
                    
                    if (isUnreadLocally && hasReply) {
                        val popAnim = android.view.animation.ScaleAnimation(
                            1.0f, 1.05f, 1.0f, 1.05f,
                            android.view.animation.Animation.RELATIVE_TO_SELF, 0.5f,
                            android.view.animation.Animation.RELATIVE_TO_SELF, 0.5f
                        )
                        popAnim.duration = 300
                        popAnim.repeatMode = android.view.animation.Animation.REVERSE
                        popAnim.repeatCount = 3
                        view.postDelayed({ view.startAnimation(popAnim) }, 300)
                        }
                }
    }
}
