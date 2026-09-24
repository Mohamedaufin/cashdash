package com.cash.dash

import java.util.Locale

/**
 * Works out which app a screenshot came from, using the file name.
 *
 * Only some makers put it in the file name. Samsung writes
 * `Screenshot_20260923_231638_supermoney.jpg` and Xiaomi writes the package as
 * `..._com.swiggy.android.jpg`, but Pixel, stock Android and OnePlus write a bare
 * timestamp — which is most phones. So the file name is the reliable path when it
 * exists, and [appInText] is the fallback for everyone else.
 *
 * Which app it was decides how the receipt reads: a payment app shows a payee worth
 * extracting, whereas a Swiggy or Myntra order page has no payee at all — the app
 * itself is what the money went to.
 */
internal object ScreenshotSource {

    /** Apps whose receipts name a payee, so the existing payee extraction applies. */
    private val paymentApps = setOf(
        "gpay", "googlepay", "google pay", "tez", "phonepe", "paytm", "cred",
        "supermoney", "super.money", "superpay", "bhim", "amazonpay", "navi", "slice",
        "fi", "fimoney", "jupiter", "mobikwik", "freecharge", "whatsapp", "samsungpay",
        "tataneu", "groww", "kiwi", "fampay", "bharatpe", "payzapp", "airtel",
        "airtelthanks", "ippb", "cashdash"
    )

    /** A page in a browser could be anything, so it gets the payment-app treatment too. */
    private val browsers = setOf(
        "chrome", "firefox", "samsunginternet", "internet", "edge", "opera", "brave",
        "duckduckgo", "browser", "safari", "vivaldi", "mi browser", "uc browser"
    )

    /** Brands whose own spelling is not just a capitalised first letter. */
    private val brandCasing = mapOf(
        "swiggy" to "Swiggy", "zomato" to "Zomato", "myntra" to "Myntra",
        "amazon" to "Amazon", "flipkart" to "Flipkart", "zepto" to "Zepto",
        "blinkit" to "Blinkit", "bigbasket" to "BigBasket", "dunzo" to "Dunzo",
        "uber" to "Uber", "ola" to "Ola", "rapido" to "Rapido", "meesho" to "Meesho",
        "ajio" to "AJIO", "nykaa" to "Nykaa", "bookmyshow" to "BookMyShow",
        "netflix" to "Netflix", "spotify" to "Spotify", "hotstar" to "Hotstar",
        "jiohotstar" to "JioHotstar", "irctc" to "IRCTC", "makemytrip" to "MakeMyTrip",
        "goibibo" to "Goibibo", "redbus" to "redBus", "cleartrip" to "Cleartrip",
        "dominos" to "Domino's", "kfc" to "KFC", "mcdonalds" to "McDonald's",
        "starbucks" to "Starbucks", "decathlon" to "Decathlon", "lenskart" to "Lenskart",
        "pharmeasy" to "PharmEasy", "1mg" to "Tata 1mg", "practo" to "Practo",
        "jiomart" to "JioMart", "dmart" to "DMart", "croma" to "Croma",
        "relianceDigital" to "Reliance Digital", "urbancompany" to "Urban Company"
    )

    /**
     * Pulls the app name out of a screenshot file name, or null when there isn't one.
     *
     * Xiaomi and stock Android write only a timestamp, so the caller has to cope with
     * null rather than assume every screenshot is attributable.
     */
    fun appName(fileName: String?): String? {
        val base = fileName?.substringBeforeLast('.')?.trim().orEmpty()
        if (base.isEmpty()) return null
        // Only a screenshot's own name carries the app. A WhatsApp photo called
        // IMG-20260924-WA0003 has no underscore, so the whole file name came back as
        // the "app" and was shown to the user as the payee.
        if (!base.startsWith("screenshot", ignoreCase = true)) return null
        if (!base.contains('_')) return null

        var token = base.substringAfterLast('_').trim()
        // OnePlus and similar append the package: com.swiggy.android -> swiggy.
        if (token.count { it == '.' } >= 2 && token.startsWith("com.", ignoreCase = true)) {
            token = token.split('.').getOrNull(1)?.takeIf { it.isNotBlank() } ?: token
        } else if (token.contains('.') && !token.equals("super.money", ignoreCase = true)) {
            token = token.substringAfterLast('.')
        }

        // Anything that is only digits, punctuation or a stray date fragment is a
        // timestamp rather than an app.
        if (token.length < 2 || token.none { it.isLetter() }) return null
        if (token.all { it.isDigit() || it == '-' }) return null
        if (token.equals("screenshot", ignoreCase = true)) return null
        // An app name is letters, possibly with a digit or two. Anything mostly digits
        // or dashes is a timestamp fragment.
        if (token.count { it.isLetter() } < token.length / 2) return null
        if (token.any { !it.isLetterOrDigit() && it != '.' && it != '-' }) return null
        return token
    }

    /** True when the app names a payee on its receipts, or is a browser. */
    fun namesAPayee(app: String): Boolean {
        val key = app.lowercase(Locale.ENGLISH).replace(" ", "")
        return paymentApps.any { it.replace(" ", "") == key } ||
            browsers.any { it.replace(" ", "") == key }
    }

    /**
     * Finds a known shop or delivery brand in the recognised text.
     *
     * The fallback for every phone that names screenshots with only a timestamp. The
     * most prominently rendered match wins, because a brand in the header is the source
     * app whereas one buried in an order line is just an item. Payment apps are not
     * looked for here: on their receipts the payee is the answer, not the app.
     */
    fun appInText(lines: List<ReceiptLine>): String? {
        var best: Pair<Int, String>? = null
        for (line in lines) {
            val words = Regex("[A-Za-z0-9']+").findAll(line.text.lowercase(Locale.ENGLISH))
                .map { it.value }
                .toSet()
            for (brand in brandCasing.keys) {
                // Multi-word brands are matched against the line, single words against
                // its tokens, so "amazon" cannot fire on "amazonpay".
                val hit = if (brand.contains(' ')) line.text.contains(brand, ignoreCase = true)
                    else brand in words
                if (!hit) continue
                if (best == null || line.height > best!!.first) best = line.height to brand
            }
        }
        return best?.second
    }

    /** The app's own spelling where known, otherwise a tidy capitalisation. */
    fun displayName(app: String): String {
        val key = app.lowercase(Locale.ENGLISH)
        brandCasing[key]?.let { return it }
        // Already mixed or upper case (CRED, IRCTC) is the brand's own styling.
        if (app.any { it.isUpperCase() } && app != key) return app
        if (app.all { it.isUpperCase() || !it.isLetter() }) return app
        return key.replaceFirstChar { it.titlecase(Locale.ENGLISH) }
    }
}
