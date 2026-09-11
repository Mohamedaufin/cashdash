package com.cash.dash

import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.*
import android.widget.FrameLayout
import androidx.core.content.ContextCompat
import com.airbnb.lottie.LottieAnimationView
import com.google.android.material.button.MaterialButtonToggleGroup
import java.util.*
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowCompat
import kotlin.math.abs
import java.text.SimpleDateFormat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ReportActivity : ThemedActivity() {

    private lateinit var viewPager: androidx.viewpager2.widget.ViewPager2

    private lateinit var btnPeriodSelect: Button
    private lateinit var toggleMode: MaterialButtonToggleGroup
    private lateinit var layoutCustomDates: View
    private lateinit var btnCustomStart: View
    private lateinit var btnCustomEnd: View
    private lateinit var tvCustomStart: TextView
    private lateinit var tvCustomEnd: TextView

    private var currentMonth = Calendar.getInstance().get(Calendar.MONTH)
    private var currentYear = Calendar.getInstance().get(Calendar.YEAR)
    private var selectedWeekIndex = 0
    private var isMonthlyMode = true
    private var isCustomMode = false
    private var customStartMillis = 0L
    private var customEndMillis = 0L
    private var isGenerating = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_report)

        val topBar = findViewById<View>(R.id.topBar)

        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.reportRoot)) { _, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            val navBarHeight = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom

            // Top Bar Margin
            val topBarView = findViewById<View>(R.id.topBar)
            val params = topBarView.layoutParams as androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
            params.topMargin = systemBars.top
            topBarView.layoutParams = params

            // Sticky Download Button (Absolute Edge-to-Edge)
            val btnDownload = findViewById<View>(R.id.btnDownloadFinal)
            val btnParams = btnDownload.layoutParams as android.view.ViewGroup.MarginLayoutParams
            btnParams.bottomMargin = navBarHeight
            btnDownload.layoutParams = btnParams

            insets
        }


        viewPager = findViewById(R.id.viewPager)
        viewPager.adapter = ReportPagerAdapter()
        viewPager.registerOnPageChangeCallback(object : androidx.viewpager2.widget.ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                val btnId = when(position) { 0 -> R.id.btnWeekly; 1 -> R.id.btnMonthly; else -> R.id.btnCustom }
                if (toggleMode.checkedButtonId != btnId) toggleMode.check(btnId)
            }
        })
        btnPeriodSelect = findViewById(R.id.btnPeriodSelect)
        toggleMode = findViewById(R.id.toggleMode)
        layoutCustomDates = findViewById(R.id.layoutCustomDates)
        btnCustomStart = findViewById(R.id.btnCustomStart)
        btnCustomEnd = findViewById(R.id.btnCustomEnd)
        tvCustomStart = findViewById(R.id.tvCustomStart)
        tvCustomEnd = findViewById(R.id.tvCustomEnd)

        // Prefill the custom range, matching Generate Statement, which opens on
        // the current month to date rather than an empty "Select..." placeholder.
        // This also means the existing "Select start and end dates first" guard in
        // generateDownload() can no longer be hit from a fresh screen.
        customStartMillis = Calendar.getInstance().apply {
            set(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        customEndMillis = System.currentTimeMillis()
        SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).let { fmt ->
            tvCustomStart.text = fmt.format(Date(customStartMillis))
            tvCustomEnd.text = fmt.format(Date(customEndMillis))
        }

        // White Theme UI Refinement
        if (ThemeHelper.isWhiteTheme(this)) {
            btnPeriodSelect.compoundDrawableTintList = android.content.res.ColorStateList.valueOf(Color.BLACK)
        }

        findViewById<View>(R.id.btnBack).setOnClickListener { finish() }
        findViewById<View>(R.id.btnDownloadFinal).setOnClickListener { generateDownload() }

        btnCustomStart.setOnClickListener { showDatePicker(true) }
        btnCustomEnd.setOnClickListener { showDatePicker(false) }

        // Once, at setup. The lists it installs answer for state_checked, so they follow
        // the group from here on; it used to run only from the listener below, which left
        // the initially checked tab on Material's own violet until something was tapped.
        styleToggleTabs()

        toggleMode.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (isChecked) {
                isMonthlyMode = (checkedId == R.id.btnMonthly)
                isCustomMode = (checkedId == R.id.btnCustom)
                
                val targetPage = when (checkedId) {
                    R.id.btnWeekly -> 0
                    R.id.btnMonthly -> 1
                    else -> 2
                }
                if (viewPager.currentItem != targetPage) {
                    viewPager.currentItem = targetPage
                }

                if (isCustomMode) {
                    btnPeriodSelect.visibility = View.GONE
                    layoutCustomDates.visibility = View.VISIBLE
                    if (customStartMillis > 0 && customEndMillis > 0) {
                        viewPager.adapter?.notifyDataSetChanged()
                    }
                } else {
                    btnPeriodSelect.visibility = View.VISIBLE
                    layoutCustomDates.visibility = View.GONE
                    lifecycleScope.launch(Dispatchers.IO) {
                        // getWeekIndexForNow() resolves AFTER the pages below have already been
                        // built with whatever selectedWeekIndex happened to hold — 0 on a fresh
                        // open. updatePeriodLabel() then rewrote only the dropdown, so the
                        // selector advertised the current week while the report underneath still
                        // held the previous one's figures. That is a wrong number under a right
                        // label, so the pages have to be rebuilt whenever the index actually moves.
                        val resolvedIndex = if (!isMonthlyMode) getWeekIndexForNow() else selectedWeekIndex
                        val indexChanged = resolvedIndex != selectedWeekIndex
                        selectedWeekIndex = resolvedIndex
                        withContext(Dispatchers.Main) {
                            updatePeriodLabel()
                            if (indexChanged) viewPager.adapter?.notifyDataSetChanged()
                        }
                    }
                }
            }
        }

        btnPeriodSelect.setOnClickListener { showPeriodPicker() }

        updatePeriodLabel()
        viewPager.adapter?.notifyDataSetChanged()
    }

    private fun showDatePicker(isStart: Boolean) {
        val cal = Calendar.getInstance()
        val currentMillis = if (isStart) (if (customStartMillis > 0) customStartMillis else cal.timeInMillis) 
                            else (if (customEndMillis > 0) customEndMillis else cal.timeInMillis)
        cal.timeInMillis = currentMillis
        
        android.app.DatePickerDialog(this, ThemeHelper.getDatePickerTheme(this), { _, year, month, day ->
            val sel = Calendar.getInstance().apply { 
                set(year, month, day, if(isStart) 0 else 23, if(isStart) 0 else 59, if(isStart) 0 else 59) 
            }.timeInMillis
            
            if (isStart) {
                if (customEndMillis > 0 && sel > customEndMillis) {
                    ToastHelper.showToast(this, "Start date cannot be after end date")
                    return@DatePickerDialog
                }
                customStartMillis = sel
                tvCustomStart.text = SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(Date(sel))
            } else {
                if (customStartMillis > 0 && sel < customStartMillis) {
                    ToastHelper.showToast(this, "End date cannot be before start date")
                    return@DatePickerDialog
                }
                customEndMillis = sel
                tvCustomEnd.text = SimpleDateFormat("MMM d, yyyy", Locale.getDefault()).format(Date(sel))
            }
            
            if (customStartMillis > 0 && customEndMillis > 0) {
                viewPager.adapter?.notifyDataSetChanged()
            }
        }, cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)).show()
    }

    private fun updatePeriodLabel() {
        lifecycleScope.launch(Dispatchers.IO) {
            if (isMonthlyMode) {
                val sdf = SimpleDateFormat("MMMM yyyy", Locale.getDefault())
                val cal = Calendar.getInstance().apply { set(currentYear, currentMonth, 1) }
                val label = sdf.format(cal.time)
                withContext(Dispatchers.Main) {
                    btnPeriodSelect.text = label
                }
            } else {
                val weeks = FinancialInsightsManager.calculateWeeklyTrends(this@ReportActivity, currentMonth, currentYear)
                val label = if (selectedWeekIndex < weeks.size) {
                    "${weeks[selectedWeekIndex].weekLabel} (${weeks[selectedWeekIndex].dates})"
                } else {
                    "Select Week"
                }
                withContext(Dispatchers.Main) {
                    btnPeriodSelect.text = label
                }
            }
        }
    }

    private suspend fun getWeekIndexForNow(): Int = withContext(Dispatchers.IO) {
        val cal = Calendar.getInstance()
        if (currentMonth != cal.get(Calendar.MONTH) || currentYear != cal.get(Calendar.YEAR)) return@withContext 0
        
        val weeks = FinancialInsightsManager.calculateWeeklyTrends(this@ReportActivity, currentMonth, currentYear)
        val sdf = SimpleDateFormat("MMM d", Locale.getDefault())
        val nowCal = Calendar.getInstance()
        
        for (i in weeks.indices) {
            val parts = weeks[i].dates.split(" - ")
            if (parts.size == 2) {
                try {
                    val start = sdf.parse(parts[0])
                    val end = sdf.parse(parts[1])
                    if (start != null && end != null) {
                        val startCal = Calendar.getInstance().apply { 
                            time = start
                            set(Calendar.YEAR, currentYear)
                        }
                        val endCal = Calendar.getInstance().apply { 
                            time = end
                            set(Calendar.YEAR, currentYear)
                            set(Calendar.HOUR_OF_DAY, 23)
                            set(Calendar.MINUTE, 59)
                        }
                        if (nowCal.timeInMillis in startCal.timeInMillis..endCal.timeInMillis) return@withContext i
                    }
                } catch (e: Exception) {}
            }
        }
        return@withContext if (weeks.isNotEmpty()) weeks.size - 1 else 0
    }

    private fun showPeriodPicker() {
        val months = arrayOf("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")
        
        val pad = (24 * resources.displayMetrics.density).toInt()
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
            val bgResId = ThemeHelper.getDrawable(this@ReportActivity, R.drawable.bg_transaction)
            setBackgroundResource(bgResId)
        }

        val titleView = TextView(this).apply {
            text = if (isMonthlyMode) "Select Month" else "Select Month First"
            setTextColor(ThemeHelper.resolveColorAttr(this@ReportActivity, R.attr.textPrimaryColor))
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, resources.getDimension(R.dimen.text_subhead))
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, (20 * resources.displayMetrics.density).toInt())
        }
        container.addView(titleView)

        val picker = NumberPicker(this).apply {
            minValue = 0
            maxValue = 11
            value = currentMonth
            displayedValues = months
        }
        
        val pickerContainer = FrameLayout(this).apply {
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = android.view.Gravity.CENTER
            }
            layoutParams = params
            addView(picker)
        }
        container.addView(pickerContainer)

        val actionsContainer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.END
            setPadding(0, (20 * resources.displayMetrics.density).toInt(), 0, 0)
        }

        val dialogBuilder = androidx.appcompat.app.AlertDialog.Builder(this)
        dialogBuilder.setView(container)
        val dialog = dialogBuilder.create()
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)

        val btnOk = Button(this).apply {
            text = "OK"
            // The button is transparent over `container`, whose background comes from
            // setBackgroundResource(bgResId) and is therefore theme-swapped. A fixed white
            // here disappeared against the light drawable on the White theme.
            setTextColor(ThemeHelper.resolveColorAttr(this@ReportActivity, R.attr.textPrimaryColor))
            setBackgroundColor(Color.TRANSPARENT)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(null, android.graphics.Typeface.BOLD)
            setOnClickListener {
                dialog.dismiss()
                currentMonth = picker.value
                if (isMonthlyMode) {
                    updatePeriodLabel()
                    viewPager.adapter?.notifyDataSetChanged()
                } else {
                    showWeekPicker()
                }
            }
        }
        actionsContainer.addView(btnOk)
        container.addView(actionsContainer)

        dialog.show()
        val width = (resources.displayMetrics.widthPixels * 0.85).toInt()
        dialog.window?.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    private fun showWeekPicker() {
        lifecycleScope.launch(Dispatchers.IO) {
            val weeks = FinancialInsightsManager.calculateWeeklyTrends(this@ReportActivity, currentMonth, currentYear)
            val weekLabels = weeks.map { "${it.weekLabel} (${it.dates})" }.toTypedArray()
            
            withContext(Dispatchers.Main) {
                val pad = (24 * resources.displayMetrics.density).toInt()
                val container = LinearLayout(this@ReportActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(pad, pad, pad, pad)
                    val bgResId = ThemeHelper.getDrawable(this@ReportActivity, R.drawable.bg_transaction)
                    setBackgroundResource(bgResId)
                }

                val titleView = TextView(this@ReportActivity).apply {
                    text = "Select Week for ${java.text.DateFormatSymbols().months[currentMonth]}"
                    setTextColor(ThemeHelper.resolveColorAttr(this@ReportActivity, R.attr.textPrimaryColor))
                    setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, resources.getDimension(R.dimen.text_subhead))
                    setTypeface(null, android.graphics.Typeface.BOLD)
                    gravity = android.view.Gravity.CENTER
                    setPadding(0, 0, 0, (20 * resources.displayMetrics.density).toInt())
                }
                container.addView(titleView)

                val listView = ListView(this@ReportActivity).apply {
                    val layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    )
                    this.layoutParams = layoutParams
                    // Separator between weeks. ?attr/dividerColor is defined by every
                    // theme against its own surface (#1AFFFFFF on the dark themes,
                    // #20000000 on White), so this reads correctly in all three rather
                    // than needing a hardcoded translucent white.
                    divider = android.graphics.drawable.ColorDrawable(
                        ThemeHelper.resolveColorAttr(this@ReportActivity, R.attr.dividerColor)
                    )
                    dividerHeight = resources.displayMetrics.density.toInt().coerceAtLeast(1)
                }
                container.addView(listView)

                val dialogBuilder = androidx.appcompat.app.AlertDialog.Builder(this@ReportActivity)
                dialogBuilder.setView(container)
                val dialog = dialogBuilder.create()
                dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)

                val listAdapter = object : ArrayAdapter<String>(this@ReportActivity, android.R.layout.simple_list_item_1, weekLabels) {
                    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                        val view = super.getView(position, convertView, parent) as TextView
                        view.setTextColor(ThemeHelper.resolveColorAttr(this@ReportActivity, R.attr.textPrimaryColor))
                        view.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15f)
                        view.setPadding(
                            (12 * resources.displayMetrics.density).toInt(),
                            (14 * resources.displayMetrics.density).toInt(),
                            (12 * resources.displayMetrics.density).toInt(),
                            (14 * resources.displayMetrics.density).toInt()
                        )
                        return view
                    }
                }
                listView.adapter = listAdapter

                listView.setOnItemClickListener { _, _, position, _ ->
                    dialog.dismiss()
                    selectedWeekIndex = position
                    updatePeriodLabel()
                    viewPager.adapter?.notifyDataSetChanged()
                }

                dialog.show()
                val width = (resources.displayMetrics.widthPixels * 0.85).toInt()
                dialog.window?.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
            }
        }
    }

    private fun loadReportForPage(container: LinearLayout, pageIndex: Int) {
        if (isGenerating) return
        isGenerating = true
        
        container.removeAllViews()
        
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val isMonthly = (pageIndex == 1)
                val isCustom = (pageIndex == 2)
                val insights = FinancialInsightsManager.generateReport(
                    this@ReportActivity, isMonthly, isCustom, customStartMillis, customEndMillis, currentMonth, currentYear, if (isMonthly) -1 else selectedWeekIndex
                )
                withContext(Dispatchers.Main) {
                    isGenerating = false
                    renderReport(insights, container)
                }
            } catch (e: Exception) {
                android.util.Log.e("ReportActivity", "Error generating advisory report", e)
                withContext(Dispatchers.Main) {
                    isGenerating = false
                    addCard(container, "Advisory Offline", "Error", "Quantum engine error: ${e.localizedMessage}", R.drawable.ic_glass_menu_vector)
                }
            }
        }
    }

    private fun renderReport(insights: FinancialInsightsManager.AdvisoryInsights, container: LinearLayout) {
        try {
            container.removeAllViews()

            // Nothing was spent in this period, so show the breakdown card — which says so in
            // words — and render none of the analysis below it.
            //
            // The condition used to also require topCategories to be empty, which almost never
            // holds: a user with allocations set up has categories, they just have zero against
            // them this week. The result was a whole report built out of zeroes, in which
            // "Travel — Dominates 0% of budget" sat above four ₹0 (0%) rows, beside a summary
            // reading "↓100% vs previous period". Every line was vacuous and several were
            // actively misleading.
            if (insights.totalSpent <= 0f) {
                injectPieChartCard(insights, container)
                return
            }

            // 0. Spend breakdown
            if (insights.topCategories.isNotEmpty()) {
                injectPieChartCard(insights, container)
            }

            // 1. Summary
            val modeLabel = if (insights.isCustomMode) "Custom" else if (isMonthlyMode) "Monthly" else "Weekly"
            addCard(container, "$modeLabel Spending Summary", 
                "₹${insights.totalSpent.toInt()}", 
                "${if (insights.changePercent >= 0) "↑" else "↓"}${abs(insights.changePercent).toInt()}% vs previous period",
                R.drawable.ic_glass_menu_vector) {
                addInfoRow("Daily Average", "₹${insights.dailyAverage.toInt()}")
            }

            val topCategoryName = insights.topCategories.firstOrNull()?.category ?: "None"
            val displayTopCategoryName = if (topCategoryName.equals("no choice", ignoreCase = true)) "No Allocation" else topCategoryName
            addCard(container, "Category-wise Attribution", 
                displayTopCategoryName, 
                "Dominates ${insights.topCategories.firstOrNull()?.percentage?.toInt() ?: 0}% of budget",
                R.drawable.ic_category_transport) {
                insights.topCategories.take(5).forEach {
                    val displayCatName = if (it.category.equals("no choice", ignoreCase = true)) "No Allocation" else it.category
                    addInfoRow(displayCatName, "₹${it.amount.toInt()} (${it.percentage.toInt()}%)")
                }
            }

            // 3. Weekly/Daily Patterns
            if (insights.isCustomMode) {
                addCard(container, "Dominant Spending Dates", 
                    if (insights.dailyPatterns.isNotEmpty()) insights.dailyPatterns[0].dayLabel else "N/A", 
                    "Highest consumption dates in range",
                    R.drawable.ic_glass_menu_vector) {
                    insights.dailyPatterns.forEach { 
                        addInfoRow(it.dayLabel, "₹${it.amount.toInt()}")
                    }
                }
            } else if (isMonthlyMode) {
                val topWeek = insights.topWeeks.firstOrNull()
                addCard(container, "Weekly Spending Pattern", 
                    topWeek?.weekLabel ?: "N/A", 
                    "Peak consumption week",
                    R.drawable.ic_glass_menu_vector) {
                    insights.topWeeks.forEach { 
                        addInfoRow(it.weekLabel, "₹${it.amount.toInt()}", it.dates)
                    }
                }
            } else {
                val peak = insights.dailyPatterns.find { it.isPeak }
                addCard(container, "Daily Spending Pattern", 
                    peak?.dayLabel ?: "N/A", 
                    "Peak velocity: ₹${peak?.amount?.toInt() ?: 0}",
                    R.drawable.ic_glass_menu_vector) {
                    insights.dailyPatterns.forEach { 
                        addInfoRow(it.dayLabel, "₹${it.amount.toInt()}", if (it.isPeak) "PEAK" else if (it.isLow) "LOW" else null)
                    }
                }
            }

            // 4. Budget & Allocation Limits (Weekly Focus)
            if (!isMonthlyMode) {
                addCard(container, "Allocation Limit Analysis", 
                    "${insights.budgetStatus.categoryProgress.count { it.percent > 100 }} Crossed", 
                    "Checking targets vs actuals",
                    R.drawable.ic_plus) {
                    insights.budgetStatus.categoryProgress.forEach {
                        val diffPer = (it.percent - 100).toInt()
                        val status = when {
                            it.percent > 100f -> "Used: ₹${it.spent.toInt()} (+$diffPer%)"
                            it.percent > 0f -> "Used: ₹${it.spent.toInt()} (${(it.percent - 100).toInt()}%)"
                            else -> "No spent recorded"
                        }
                        val displayCatName = if (it.category.equals("no choice", ignoreCase = true)) "No Allocation" else it.category
                        addInfoRow(displayCatName, "Original limit: ₹${it.budget}", status)
                    }
                }
            }



        } catch (e: Exception) {
            android.util.Log.e("ReportActivity", "Error rendering advisory report", e)
            addCard(container, "Advisory Offline", "Error", "Quantum engine error: ${e.localizedMessage}", R.drawable.ic_glass_menu_vector)
        }
    }

    private fun injectPieChartCard(insights: FinancialInsightsManager.AdvisoryInsights, container: LinearLayout) {
        val summaries = insights.topCategories
        val dp = resources.displayMetrics.density
        val ta = obtainStyledAttributes(intArrayOf(R.attr.cardBackground))
        val cardBg = ta.getDrawable(0)
        ta.recycle()

        // Main Wrapper Card
        val cardWrapper = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).also { it.bottomMargin = (20 * dp).toInt() }
            background = cardBg
            val pad = (16 * dp).toInt()
            setPadding(pad, pad, pad, pad)
        }

        // 1. Title for the Chart with Total Budget
        val tvHeader = TextView(this).apply {
            text = "TOTAL SPENT: ₹${insights.totalSpent.toInt()}  |  ${insights.periodLabel}"
            setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textMutedColor))
            textSize = 10f
            letterSpacing = 0.1f
            typeface = Typeface.DEFAULT_BOLD
            gravity = android.view.Gravity.CENTER
        }
        cardWrapper.addView(tvHeader)

        // Nothing was spent in this period. Rendering the breakdown anyway produces a column
        // of identical "₹0 • 0%" rows above empty bars, which looks like the screen failed to
        // load rather than like an answer. Say the answer in words instead.
        //
        // This is not a rare edge: it is what every new user sees for their first week, and
        // what any user sees on a quiet week.
        if (insights.totalSpent <= 0f) {
            val emptyLine = TextView(this).apply {
                text = "No spending recorded in this period"
                setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textPrimaryColor))
                textSize = 15f
                typeface = Typeface.DEFAULT_BOLD
                gravity = android.view.Gravity.CENTER
                setPadding(0, (26 * dp).toInt(), 0, (6 * dp).toInt())
            }
            val emptyHint = TextView(this).apply {
                text = if (summaries.isEmpty()) {
                    "Set up an allocation and record an expense to see your breakdown here."
                } else {
                    "Record an expense to see your breakdown here."
                }
                setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textMutedColor))
                textSize = 12f
                gravity = android.view.Gravity.CENTER
                setPadding((24 * dp).toInt(), 0, (24 * dp).toInt(), (26 * dp).toInt())
            }
            cardWrapper.addView(emptyLine)
            cardWrapper.addView(emptyHint)
            container.addView(cardWrapper, 0)
            return
        }

        // 2. The breakdown, as a ranked bar list.
        //
        // This replaced a 3D pie chart, and the reason is accuracy rather than taste. A pie
        // drawn in perspective does not encode its values honestly: the tilt foreshortens the
        // slices at the back and the extruded side wall adds visual mass to whichever slice is
        // at the front. On real data from this app — Shopping at exactly 50% of ₹690 — the
        // front slice read as roughly 70% of the graphic. A chart that misstates the number
        // printed beside it is worse than no chart.
        //
        // Bar length is linear in the value, so 50% is half the width and nothing is hidden
        // behind anything else. It also degrades properly at both ends, which the pie did not:
        // a single category was an undifferentiated disc, and a ₹1 category was a sliver too
        // thin to see at all despite having a legend entry.
        //
        // Ranked high to low, because the first question anyone asks a spend breakdown is
        // "what was the biggest", and sorting answers it before the numbers are read.
        val breakdownContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).also { it.topMargin = (18 * dp).toInt() }
        }
        val legendContainer = breakdownContainer

        val colorPalette = intArrayOf(
            Color.parseColor("#7C5CFC"), Color.parseColor("#FCA311"), 
            Color.parseColor("#00F5FF"), Color.parseColor("#FF4D6D"), 
            Color.parseColor("#70E000"), Color.parseColor("#3D5AFE"),
            Color.parseColor("#FF1744"), Color.parseColor("#00E5FF"),
            Color.parseColor("#76FF03"), Color.parseColor("#D500F9"),
            Color.parseColor("#1DE9B6"), Color.parseColor("#FF9100"),
            Color.parseColor("#F50057"), Color.parseColor("#00B0FF"),
            Color.parseColor("#C6FF00"), Color.parseColor("#651FFF")
        )

        // Ranked, so the largest spend is always the first thing read.
        val ranked = summaries.sortedByDescending { it.amount }
        val largest = ranked.firstOrNull()?.amount ?: 0f
        val trackColor = ThemeHelper.resolveColorAttr(this, R.attr.progressTrackColor)

        ranked.forEachIndexed { index, summary ->
            val swatch = colorPalette[index % colorPalette.size]

            val row = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, (9 * dp).toInt(), 0, (9 * dp).toInt())
            }

            // --- name and figures on one line ---
            val labelRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = android.view.Gravity.CENTER_VERTICAL
            }

            val indicator = View(this).apply {
                layoutParams = LinearLayout.LayoutParams((10 * dp).toInt(), (10 * dp).toInt())
                background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(swatch)
                }
            }
            labelRow.addView(indicator)

            val nameTv = TextView(this).apply {
                val displayCatName = if (summary.category.equals("no choice", ignoreCase = true)) "No Allocation" else summary.category
                text = displayCatName.uppercase()
                setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textPrimaryColor))
                textSize = 13f
                setPadding((10 * dp).toInt(), 0, 0, 0)
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            labelRow.addView(nameTv)

            val statsTv = TextView(this).apply {
                text = "₹${summary.amount.toInt()}  •  ${summary.percentage.toInt()}%"
                setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textPrimaryColor))
                textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                gravity = android.view.Gravity.END
            }
            labelRow.addView(statsTv)
            row.addView(labelRow)

            // --- the bar ---
            //
            // Scaled against the LARGEST category rather than the total. Against the total,
            // a realistically spread month leaves every bar stubby and hard to compare; against
            // the largest, the top bar fills the width and the rest are read as fractions of it.
            // The percentage of the total is already stated in text on the line above, so no
            // information is lost by doing this.
            //
            // Widths come from layout weights, so they are correct on the first frame without
            // waiting for a measure pass to learn how wide the card is.
            val fraction = if (largest > 0f) (summary.amount / largest) else 0f
            // A category with real spend must never render as nothing: ₹1 of ₹690 is 0.3% of
            // the bar and would vanish, yet it is exactly the kind of entry a person is trying
            // to find when they open this screen.
            val drawn = when {
                summary.amount <= 0f -> 0f
                else -> fraction.coerceAtLeast(0.035f)
            }

            val barTrack = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    (8 * dp).toInt()
                ).also { it.topMargin = (7 * dp).toInt() }
                weightSum = 1f
                background = android.graphics.drawable.GradientDrawable().apply {
                    cornerRadius = 4 * dp
                    setColor(trackColor)
                }
            }

            if (drawn > 0f) {
                val fill = View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, drawn)
                    background = android.graphics.drawable.GradientDrawable().apply {
                        cornerRadius = 4 * dp
                        setColor(swatch)
                    }
                }
                barTrack.addView(fill)
            }
            if (drawn < 1f) {
                barTrack.addView(View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f - drawn)
                })
            }

            row.addView(barTrack)
            legendContainer.addView(row)
        }
        cardWrapper.addView(legendContainer)

        container.addView(cardWrapper, 0) // Insert at top of report
    }

    private fun addEmptyStateCard(container: LinearLayout) {
        addCard(container, "Data Insufficiency", "₹0", "Add more transactions to fuel AI strategy", R.drawable.ic_glass_menu_vector)
    }

    private fun addCard(container: LinearLayout, title: String, value: String, subtitle: String, iconRes: Int, builder: (LinearLayout.() -> Unit)? = null) {
        val card = layoutInflater.inflate(R.layout.item_report_card, container, false)
        card.findViewById<TextView>(R.id.cardTitle).text = title
        card.findViewById<TextView>(R.id.cardValue).text = value
        card.findViewById<TextView>(R.id.cardSubtitle).text = subtitle
        card.findViewById<ImageView>(R.id.cardIcon).setImageResource(iconRes)
        
        val extra = card.findViewById<LinearLayout>(R.id.cardExtraContainer)
        if (builder != null) {
            extra.visibility = View.VISIBLE
            extra.builder()
        }
        
        container.addView(card)
    }

    private fun LinearLayout.addInfoRow(label: String, value: String, sub: String? = null) {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 8, 0, 8)
        }
        val labelTv = TextView(context).apply {
            text = label
            setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textMutedColor))
            textSize = 14f
            layoutParams = LinearLayout.LayoutParams(0, -2, 1f)
        }
        val valTv = TextView(context).apply {
            text = value
            setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textPrimaryColor))
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity = android.view.Gravity.END
        }
        row.addView(labelTv)
        row.addView(valTv)
        addView(row)
        
        if (sub != null) {
            val subTv = TextView(context).apply {
                text = sub
                setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textMutedColor))
                textSize = 12f
                setPadding(0, 0, 0, 8)
            }
            addView(subTv)
        }
    }

    private fun LinearLayout.addInsightBullet(text: String) {
        val tv = TextView(context).apply {
            this.text = "• $text"
            setTextColor(ThemeHelper.resolveColorAttr(context, R.attr.textPrimaryColor))
            textSize = 14f
            setPadding(0, 8, 0, 8)
            setLineSpacing(0f, 1.2f)
        }
        addView(tv)
    }

    private fun generateDownload() {
        val start: Long
        val end: Long
        if (isCustomMode) {
            if (customStartMillis == 0L || customEndMillis == 0L) {
                ToastHelper.showToast(this, "Select start and end dates first")
                return
            }
            start = customStartMillis
            end = customEndMillis
        } else {
            val cal = Calendar.getInstance().apply { set(currentYear, currentMonth, 1) }
            start = cal.timeInMillis
            cal.set(Calendar.DAY_OF_MONTH, cal.getActualMaximum(Calendar.DAY_OF_MONTH))
            end = cal.timeInMillis
        }
        
        lifecycleScope.launch(Dispatchers.IO) {
            PdfReportManager.generateAndSavePremiumReport(this@ReportActivity, start, end, isMonthlyMode, selectedWeekIndex, isCustomMode)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt("currentMonth", currentMonth)
        outState.putInt("currentYear", currentYear)
        outState.putInt("selectedWeekIndex", selectedWeekIndex)
        outState.putBoolean("isMonthlyMode", isMonthlyMode)
        outState.putBoolean("isCustomMode", isCustomMode)
        outState.putLong("customStartMillis", customStartMillis)
        outState.putLong("customEndMillis", customEndMillis)
        outState.putBoolean("isGenerating", isGenerating)
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
        currentMonth = savedInstanceState.getInt("currentMonth", currentMonth)
        currentYear = savedInstanceState.getInt("currentYear", currentYear)
        selectedWeekIndex = savedInstanceState.getInt("selectedWeekIndex", selectedWeekIndex)
        isMonthlyMode = savedInstanceState.getBoolean("isMonthlyMode", isMonthlyMode)
        isCustomMode = savedInstanceState.getBoolean("isCustomMode", isCustomMode)
        customStartMillis = savedInstanceState.getLong("customStartMillis", customStartMillis)
        customEndMillis = savedInstanceState.getLong("customEndMillis", customEndMillis)
        isGenerating = savedInstanceState.getBoolean("isGenerating", false)

        updatePeriodLabel()
        if (isCustomMode && (customStartMillis <= 0 || customEndMillis <= 0)) {
            // Wait for dates
        } else {
            viewPager.adapter?.notifyDataSetChanged()
        }
    }

    /**
     * Styles the period tabs once. Called at setup, not per selection.
     *
     * Three separate things were painting these buttons violet, and fixing one at a time
     * kept leaving a flash:
     *
     *  1. the checked state, which Material fills from colorPrimary
     *  2. the ripple, which Widget.MaterialComponents.Button.OutlinedButton also derives
     *     from colorPrimary, and which backgroundTintList does not touch
     *  3. nothing running until the first tap, so the tab checked in XML kept Material's
     *     default until the user changed it
     *
     * colorPrimary is @color/primary_purple on Black. Blue and White override it, which is
     * why the violet only ever showed on Black.
     *
     * Everything here is a ColorStateList keyed on state_checked, so it is installed once
     * and then tracks the group. Assigning flat colours per selection was what left
     * Material's default underneath to show through first.
     */
    private fun styleToggleTabs() {
        // Shared with Finminder's Cash Out / Cash In tabs; see ToggleTabStyler for why a
        // state list is required rather than a flat colour.
        ToggleTabStyler.apply(this, R.id.btnWeekly, R.id.btnMonthly, R.id.btnCustom)
    }

    inner class ReportPagerAdapter : androidx.recyclerview.widget.RecyclerView.Adapter<ReportPagerAdapter.ViewHolder>() {
        inner class ViewHolder(view: View) : androidx.recyclerview.widget.RecyclerView.ViewHolder(view) {
            val reportContent: LinearLayout = view.findViewById(R.id.reportContent)
        }
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = layoutInflater.inflate(R.layout.item_report_page, parent, false)
            return ViewHolder(view)
        }
        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            loadReportForPage(holder.reportContent, position)
        }
        override fun getItemCount() = 3
    }
}
