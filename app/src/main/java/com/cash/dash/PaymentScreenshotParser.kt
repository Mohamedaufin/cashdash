package com.cash.dash

import java.time.DateTimeException
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/** Text and position returned by on-device OCR. No image or OCR text is persisted. */
internal data class ReceiptLine(
    val text: String,
    val top: Int,
    val left: Int,
    val height: Int,
    val width: Int = 0,
    val blockId: Int = -1
)

internal data class PaymentFields(
    val isPayment: Boolean,
    val title: String?,
    val amount: Int?,
    val date: Long?,
    /** Box of the line the amount came from, so it can be re-read at higher zoom. */
    val amountBox: IntArray? = null,
    /** Evidence used to rank and reconcile amount reads from multiple OCR passes. */
    val amountEvidence: AmountEvidence? = null
)

internal enum class AmountEvidence {
    CURRENCY,
    PAYMENT_LABEL,
    GLYPH,
    BARE;

    val isReliable: Boolean get() = this != BARE
}

/** Conservative receipt extraction: uncertain fields are left for the user to enter. */
internal object PaymentScreenshotParser {
    // "received" and "credited" are the incoming half of the money verbs. Paytm titles
    // its incoming receipts "Money Received" — without them the gate rejected the whole
    // screenshot and only the amount, recovered by a separate scan, survived.
    private val successWords = Regex("(?i)\\b(successful|success|completed|complete|paid|sent|debited|received|credited)\\b")

    // "Paid to" on its own satisfies successWords, so a declined transfer was read as a
    // completed one and logged as an expense that never left the account.
    private val failureWords = Regex("(?i)(\\b(failed|failure|declined|unsuccessful|cancelled|canceled|rejected|expired|reversed)\\b|not\\s+permitted|did\\s*n[o']?t\\s+go\\s+through)")
    // App promotions, not payment status. Paytm stamps "Reward expired" over successful
    // transfers, and that banner's bare "expired" satisfied the failure check over the
    // whole receipt — the name, amount and date of a real payment were thrown away with
    // it. Promotional lines are dropped before the failure check, so "Payment Failed"
    // stays authoritative while a bonus banner loses its veto.
    private val promoWords = Regex("(?i)\\b(rewards?|cashbacks?|offers?|coupons?|promos?|promotions?|scratch\\s*cards?|bonuses?|deals?)\\b")
    // A payment app's own receipt often scrolls a history list in beneath it, and one
    // of those older transactions can read "Payment Failed" — about another transfer,
    // not this one. From a history heading down, lines are other receipts, so they
    // take no part in the failure check of the one being read.
    private val historyWords = Regex("(?i)\\b(past\\s+transactions?|transaction\\s+history|recent\\s+transactions?)\\b")
    private val paymentWords = Regex("(?i)\\b(payment|paid|sent|debited|transaction|upi|merchant|cred|gpay|phonepe|paytm)\\b")
    // These mark the start of the details list, so they have to be field labels rather
    // than any appearance of the word. A bare `\bbank\b` matched "Finance Bank Limited"
    // — the merchant's own name — which put the boundary above the amount and threw
    // away most of the receipt. `i[dl]` because OCR reads the capital I of "Id" as a
    // lowercase l often enough to matter.
    private val detailWords = Regex("(?i)\\b(transaction\\s*i[dl]|reference|ref\\s*(?:no|i[dl])|bank\\s+(?:name|a/?c|account|ref)|a/?c\\s*(?:no|number)|account\\s*(?:no|number|name|details)|paid\\s+(?:to|from)\\s+upi\\s*i[dl])\\b")
    private val statusWords = Regex("(?i)\\b(pay\\s+again|successful|success|completed|complete|debited)\\b")
    private val currencyAmount = Regex("(?i)(?:₹|rs\\.?|inr)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)")
    // Some OCR passes remove both the ₹ and the following space: "Paid ₹7,800"
    // becomes "Paid7,800". The payment verb is still strong evidence that the number
    // on this line is the headline amount.
    private val paymentLabelAmount = Regex("(?i)(?:^|\\s)(?:paid|sent|debited|received|amount|total)\\s*(?:₹|rs\\.?|inr)?\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\b")
    private val bareAmount = Regex("(?i)^(?:₹|rs\\.?|inr|r)?\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)$")

    /**
     * A single letter before the digits, which is the ₹ glyph misread.
     *
     * Paytm's "₹1" came back as "Z1", matching nothing — so there was no amount, and no
     * region for the zoom pass to re-read either. Only letters belong here, never
     * digits: a leading 7 is genuinely ambiguous, since "₹1" and "71" are identical once
     * the symbol is lost, but no real amount starts with Z or T. Stripping one of those
     * is safe, and the result can be trusted as currency-marked.
     */
    // F joins the misreads: a header re-scan of the Paytm "Money Received" receipt
    // reported the ₹ of ₹10 as F. As with Z and T, no real amount is one letter wide
    // and made of F.
    private val glyphPrefixedAmount = Regex("(?i)^[₹zt f]\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)$")
    private val explicitPayee = Regex("(?i)^(?:(?:paid|sent|transferred)\\s+)?to\\s*[:\\-]?\\s*(.+)$")

    // Money in is a transaction worth recording too, and there the other party sits
    // behind "From" or "Received from" rather than "To".
    private val receivedFrom = Regex("(?i)^(?:received\\s+)?from\\s*[:\\-]?\\s*(.+)$")
    // BHIM puts the payee under "Banking Name", far below the amount, so without this
    // the only name-shaped text left was the app's own header banner.
    private val payeeLabelOnly = Regex("(?i)^(?:(?:paid|sent|transferred)\\s+)?to\\s*[:\\-]?$|^received\\s+from\\s*[:\\-]?$|^(?:banking|payee|merchant|beneficiary)\\s+name\\s*[:\\-]?$")
    /**
     * Words that on their own describe a field or a button rather than a payee.
     *
     * The check is "every meaningful word is generic", not "contains a generic word".
     * The looser test rejected "Finance Bank Limited" for containing "bank", losing
     * half of a real merchant name, while still accepting "Date and time" because the
     * connective "and" made it look like it carried real content.
     */
    private val genericWords = setOf(
        "payment", "transaction", "upi", "id", "bank", "balance", "paid", "sent",
        "completed", "successful", "success", "cred", "gpay", "google", "phonepe",
        "paytm", "cashdash", "home", "share", "account", "receipt", "details",
        "history", "check", "from", "via", "scan", "screenshot", "amount", "total",
        "issue", "help", "support", "faq", "done", "close", "back", "menu", "view",
        "more", "call", "split", "reward", "rewards", "cashback", "earned", "date",
        "time", "method", "status", "note", "notes", "remark", "remarks", "message",
        "category", "purpose", "mode", "type", "money", "wallet", "card", "debit",
        "credit",
        // Reference-line vocabulary. "Bank Ref No" was surviving as a payee because only
        // "bank" was listed — "ref" carried the line on its own.
        "ref", "reference", "number", "txn", "utr", "vpa", "ifsc",
        // Incoming-receipt vocabulary. Without a From: line these banner and amount
        // words were the only name-shaped text left, and "Money Received" or
        // "Rupees Ten Only" became the payee.
        "received", "credited", "rupees"
    )

    /** Connectives carry no identity, so they must not rescue an all-generic line. */
    private val stopWords = setOf("and", "or", "the", "to", "of", "for", "a", "an", "at", "on", "in", "is")

    private fun isGenericName(text: String): Boolean {
        val words = Regex("[A-Za-z]+").findAll(text.lowercase(Locale.ENGLISH))
            .map { it.value }
            // A one- or two-letter token carries no identity, so it must not be the only
            // thing keeping a line of labels alive. "Transaction Id" came through as a
            // payee because OCR read "Id" as "ld", which is in no word list — the two
            // real words were both generic and the noise outvoted them.
            .filter { it !in stopWords && it.length >= 3 }
            .toList()
        return words.isEmpty() || words.all { it in genericWords }
    }
    private val monthNames = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
    private val dayMonthYear = Regex("(?i)\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s,./'’\\-]+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\\s,.'’/\\-]*(\\d{2}|\\d{4})\\b")
    private val monthDayYear = Regex("(?i)\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\\s,./'’\\-]+(\\d{1,2})(?:st|nd|rd|th)?[\\s,.'’/\\-]+(\\d{2}|\\d{4})\\b")
    private val numericDate = Regex("\\b(\\d{1,2})[./\\-](\\d{1,2})[./\\-](\\d{2}|\\d{4})\\b")
    private val monthDay = Regex("(?i)\\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\\s,./\\-]+(\\d{1,2})(?:st|nd|rd|th)?\\b")
    private val dayMonth = Regex("(?i)\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s,./\\-]+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\b")

    /**
     * @param merchantApp set when the screenshot came from a shop or delivery app
     *   rather than a payment app. Those pages have no payee to find — the app itself
     *   is what was paid — so the name is taken from the source and only the amount
     *   and date are read out of the image.
     */
    fun parse(rawLines: List<ReceiptLine>, imageHeight: Int, merchantApp: String? = null): PaymentFields {
        val lines = rawLines.map { it.copy(text = normalizeText(it.text)) }
            .filter { it.text.isNotEmpty() }
            .sortedWith(compareBy<ReceiptLine> { it.top }.thenBy { it.left })
        val allText = lines.joinToString(" ") { it.text }
        // An order page rarely says "successful" — it says "Delivered" or nothing at
        // all — so for a known shop app a currency amount is the evidence instead.
        // Requiring one stops an arbitrary screenshot becoming an expense.
        // Requiring a ₹ here was wrong: OCR drops the glyph constantly — a Zomato
        // receipt came back with "146.95" in one pass and "7146.95" in the other — so
        // the gate rejected perfectly good receipts before anything was even read.
        val looksLikePayment = successWords.containsMatchIn(allText) &&
            (paymentWords.containsMatchIn(allText) || currencyAmount.containsMatchIn(allText))
        // A receipt that says it failed is not one, whatever else it says. The check
        // runs over the receipt minus its promo lines: Paytm stamps "Reward expired"
        // over successful transfers, and the banner's bare "expired" used to reject
        // the whole screenshot before a single field was read.
        val historyStart = lines.indexOfFirst { historyWords.containsMatchIn(it.text) }
        val statusText = lines.take(if (historyStart < 0) lines.size else historyStart)
            .filterNot { promoWords.containsMatchIn(it.text) }
            .joinToString(" ") { it.text }
        if (failureWords.containsMatchIn(statusText)) return PaymentFields(false, null, null, null, null)
        // A missing success banner no longer vetoes extraction: a transaction-details
        // page or a quietly acknowledged transfer says "Successful" nowhere, and
        // discarding it whole threw away a readable name, amount and date. Every
        // non-failed screenshot is parsed from here on; isPayment only reports how
        // payment-like the text looks, and the review screen is where a wrong guess
        // gets corrected before anything is saved.
        val moneyShape = lines.any { bareAmount.matches(it.text) || currencyAmount.containsMatchIn(it.text) }
        val isPayment = looksLikePayment ||
            // A printed ₹ is payment evidence on its own; a bare number is only
            // trusted on a page already attributable to a shop or delivery app.
            currencyAmount.containsMatchIn(allText) || (merchantApp != null && moneyShape)

        val detailIndex = lines.indexOfFirst { detailWords.containsMatchIn(it.text) }
            .let { if (it < 0) lines.size else it }
        // Searched over every line rather than lines.take(detailIndex). That boundary
        // is meant to separate a receipt's header from its details list, but any detail
        // word appearing early destroys the rest: `bank` matched a merchant called
        // "Finance Bank Limited" and `RefID` matched a reference printed above the
        // amount, each time leaving the real figure outside the search. Reference
        // numbers are excluded by the ten-million cap and by preferring ₹ instead.
        // Without payment context a bare number is not an amount: a settings page's
        // battery percentage read 57 was landing on the review form as the price.
        // Only a currency-marked figure is trusted from content with no success words
        // and no attributable shop app, and even then only as the headline evidence.
        val hasPaymentContext = looksLikePayment || merchantApp != null
        val amountMatch = findAmount(lines, imageHeight)
            ?.takeUnless { it.evidence == AmountEvidence.BARE && !hasPaymentContext }
        // Same reason: when the details boundary lands too early the header is empty,
        // so fall back to searching the whole receipt for a name.
        // The receipt's own payee wins over the app it came from: a Razorpay page
        // inside Zomato names "ZOMATO LTD", which is better than the bare app name.
        // The app is the fallback for order pages that name nobody at all.
        // Scavenged names (header word clusters, names after a bare "Paid to" label)
        // need payment vocabulary on the page: without it, a settings page's section
        // heading "Battery" was the only name-shaped text and became the payee.
        // Explicit To:/From: labels are evidence on their own and stay ungated.
        val paymentVocabulary = looksLikePayment || paymentWords.containsMatchIn(allText)
        val title = (findTitle(lines, detailIndex, amountMatch?.top, paymentVocabulary)
            ?: findTitle(lines, lines.size, amountMatch?.top, paymentVocabulary)
            ?: merchantApp)?.let { preferBestSpacedDuplicate(it, lines) }
        // Prefer the receipt's main payment date over secondary dates in bank
        // details, references or a surrounding gallery UI.
        val date = if (merchantApp != null) findDate(lines, imageHeight)
            else findDate(lines.take(detailIndex), imageHeight)
                ?: findDate(lines.drop(detailIndex), imageHeight)
        return PaymentFields(isPayment, title, amountMatch?.value, date,
            amountMatch?.let { intArrayOf(it.left, it.top, it.width, it.height) },
            amountMatch?.evidence)
    }

    data class AmountMatch(val value: Int, val evidence: AmountEvidence, val top: Int, val left: Int = 0, val width: Int = 0, val height: Int = 0)

    /**
     * Reads the amount out of a crop the caller has already located as the headline figure.
     *
     * [parse] refuses anything that does not look like a payment. That is right for a whole
     * screenshot and wrong for a one-line crop: a crop of "₹1" cannot also say "Successful",
     * so the gate rejected it and returned nothing. That silently discarded correct reads —
     * the Devanagari pass recognised "₹1" on a receipt where every full-image pass had lost
     * the glyph, and the answer was thrown away here. The caller has already established the
     * screenshot is a receipt; the crop only has to be read.
     */
    fun amountInCrop(rawLines: List<ReceiptLine>): AmountMatch? {
        val lines = rawLines.map { it.copy(text = normalizeText(it.text)) }
            .filter { it.text.isNotEmpty() }
        // imageHeight 0: the crop is the amount, so there is no status bar to skip.
        return findAmount(lines, 0)
    }

    private fun findAmount(lines: List<ReceiptLine>, imageHeight: Int): AmountMatch? {
        val candidates = lines.mapNotNull { line ->
            // The status bar is not part of the receipt (time and battery often
            // look like bare amounts to OCR).
            if (imageHeight > 0 && line.top < imageHeight / 20) return@mapNotNull null
            val currency = currencyAmount.find(line.text)
            val glyph = if (currency == null) glyphPrefixedAmount.matchEntire(line.text) else null
            val labelled = if (currency == null && glyph == null) paymentLabelAmount.find(line.text) else null
            val number = (currency?.groupValues?.get(1)
                ?: glyph?.groupValues?.get(1)
                ?: labelled?.groupValues?.get(1)
                ?: bareAmount.matchEntire(line.text)?.groupValues?.get(1))
                ?.replace(",", "")?.toDoubleOrNull() ?: return@mapNotNull null
            if (number <= 0 || number > 10_000_000) return@mapNotNull null
            val evidence = when {
                currency != null -> AmountEvidence.CURRENCY
                labelled != null -> AmountEvidence.PAYMENT_LABEL
                glyph != null -> AmountEvidence.GLYPH
                else -> AmountEvidence.BARE
            }
            val evidenceScore = when (evidence) {
                AmountEvidence.CURRENCY -> 400
                AmountEvidence.PAYMENT_LABEL -> 350
                AmountEvidence.GLYPH -> 300
                AmountEvidence.BARE -> 0
            }
            val score = evidenceScore + line.height.coerceAtMost(150)
            score to AmountMatch(number.toInt(), evidence, line.top, line.left, line.width, line.height)
        }
        return candidates.maxByOrNull { it.first }?.second
    }

    private fun normalizeText(raw: String): String = raw.trim()
        .replace(Regex("(?i)(^|\\s)(paid|sent|debited|received)(?=\\d)")) {
            "${it.groupValues[1]}${it.groupValues[2]} "
        }
        .replace(Regex("\\s+"), " ")

    private fun findTitle(lines: List<ReceiptLine>, detailIndex: Int, amountTop: Int?, allowScavengedNames: Boolean): String? {
        val header = lines.take(detailIndex)
        for (i in header.indices) {
            val line = header[i]
            explicitPayee.matchEntire(line.text)?.groupValues?.get(1)?.let(::cleanName)?.let { return it }
            receivedFrom.matchEntire(line.text)?.groupValues?.get(1)?.let(::cleanName)?.let { return it }
            if (allowScavengedNames && payeeLabelOnly.matches(line.text)) {
                // Two lines ahead, not one. An avatar's initials sit to the left of the
                // name at the same height, so they sort first: "Paid to" was answering
                // "SK" rather than "Sadeesh Kumar".
                listOfNotNull(header.getOrNull(i + 1), header.getOrNull(i + 2))
                    .firstNotNullOfOrNull { candidate ->
                        cleanName(candidate.text)?.takeUnless(::isAvatarInitials)
                    }
                    ?.let { return it }
            }
        }

        // The status line is no longer a boundary. It assumes the payee appears above
        // "Successful"/"Completed", but Jupiter prints the logo, then the status, then
        // the payee — so cutting there left the logo as the only candidate and the name
        // came out as "Jupifer". The amount's position below already bounds this, and
        // the generic-word filter removes the labels.
        val headerEnd = header.size
        // "Payment Successful" is often not recognised at all when a bottom sheet dims
        // it, leaving headerEnd at the end of the receipt. The amount's position is the
        // more dependable boundary: the payee sits with the headline figure, not below
        // it among the details.
        val candidateLines = header.take(headerEnd)
            .filter { amountTop == null || it.top <= amountTop + it.height * 3 }

        if (allowScavengedNames) {
            val headerName = findHeaderName(candidateLines)
            if (headerName != null) return headerName
        }

        // Some providers show a valid "To: Name" only in the details. Never use
        // a UPI handle or the literal "UPI ID" as a person's name.
        for (i in detailIndex until lines.size) {
            val line = lines[i]
            explicitPayee.matchEntire(line.text)?.groupValues?.get(1)?.let(::cleanName)?.let { return it }
        }
        return null
    }

    private fun findHeaderName(lines: List<ReceiptLine>): String? {
        val validLines = lines.filter { line ->
            val text = line.text.trim()
            text.length >= 2 &&
                !text.any { it.isDigit() || it == '@' } &&
                text.any(Char::isLetter) &&
                !isGenericName(text) &&
                text.all { it.isLetter() || it.isWhitespace() || it in ".'-&" }
        }
        if (validLines.isEmpty()) return null

        val clusters = mutableListOf<MutableList<ReceiptLine>>()
        for (line in validLines) {
            val lastCluster = clusters.lastOrNull()
            if (lastCluster != null && isAdjacent(lastCluster.last(), line)) {
                lastCluster.add(line)
            } else {
                clusters.add(mutableListOf(line))
            }
        }

        return clusters.asReversed().firstNotNullOfOrNull { cluster ->
            cleanName(dedupeTokens(cluster.joinToString(" ") { it.text }))
        }
    }

    /**
     * Drops a word that merely repeats the one before it.
     *
     * A brand logo sits next to its own name on many receipts, and OCR reads the
     * lettering inside the logo as text: "razorpay merchant" beside a Razorpay mark
     * clustered into "arazorpay razorpay merchant". The later spelling is kept because
     * the label is rendered as real text while the logo version is an artefact of the
     * image, so it is the more likely misreading of the two.
     */
    private fun dedupeTokens(raw: String): String {
        val tokens = raw.split(" ").filter { it.isNotBlank() }
        val kept = mutableListOf<String>()
        for (token in tokens) {
            val previous = kept.lastOrNull()
            val overlaps = previous != null && minOf(previous.length, token.length) >= 4 &&
                (previous.contains(token, ignoreCase = true) || token.contains(previous, ignoreCase = true))
            if (overlaps) kept[kept.lastIndex] = token else kept.add(token)
        }
        return kept.joinToString(" ")
    }

    private fun isAdjacent(prev: ReceiptLine, next: ReceiptLine): Boolean {
        if (prev.blockId >= 0 && prev.blockId == next.blockId) return true
        val verticalGap = next.top - (prev.top + prev.height)
        val closeVertically = verticalGap in -prev.height..(maxOf(prev.height * 2, 60))
        val closeHorizontally = Math.abs(next.left - prev.left) <= maxOf(prev.height * 4, 150)
        return closeVertically && closeHorizontally
    }

    /** Two or three capitals with no vowel pattern is a monogram, not a name. */
    private fun isAvatarInitials(name: String): Boolean =
        name.length <= 3 && name.all { it.isUpperCase() || it.isWhitespace() }

    private fun cleanName(raw: String): String? {
        val name = raw.trim().trim(':', '-', ' ').replace(Regex("\\s+"), " ")
            .replace(Regex("(?i)^(?:received\\s+)?from\\s*[:\\-]?\\s+"), "")
        if (name.length !in 2..60 || name.any { it.isDigit() || it == '@' }) return null
        if (!name.any(Char::isLetter) || isGenericName(name)) return null
        if (!name.all { it.isLetter() || it.isWhitespace() || it in ".'-&" }) return null
        return name
    }

    /**
     * Reconciles duplicate OCR readings of the same counterparty without knowing any
     * person's name. A header may read `SAMPLE PERSON XY`, while a details row preserves
     * the printed initials as `SAMPLE PERSON X Y`. Their letters are identical; the
     * version with clearer token boundaries is the better transcription.
     */
    private fun preferBestSpacedDuplicate(title: String, lines: List<ReceiptLine>): String {
        fun identity(value: String): String = value.lowercase(Locale.ENGLISH)
            .filter(Char::isLetter)
        val wanted = identity(title)
        val candidates = buildList {
            add(title)
            for (line in lines) {
                val raw = explicitPayee.matchEntire(line.text)?.groupValues?.get(1)
                    ?: receivedFrom.matchEntire(line.text)?.groupValues?.get(1)
                    ?: continue
                cleanName(raw)?.takeIf { identity(it) == wanted }?.let(::add)
            }
        }
        return candidates.maxWithOrNull(
            compareBy<String> { it.split(' ').count(String::isNotBlank) }
                .thenBy { it.length }
        ) ?: title
    }

    private fun findDate(lines: List<ReceiptLine>, imageHeight: Int): Long? {
        // Pass 1: Dates with year
        for (line in lines) {
            if (imageHeight > 0 && line.top < imageHeight / 20) continue
            val text = line.text
            dayMonthYear.find(text)?.let { match ->
                parsedDate(match.groupValues[1], match.groupValues[2], match.groupValues[3])?.let { return it }
            }
            monthDayYear.find(text)?.let { match ->
                parsedDate(match.groupValues[2], match.groupValues[1], match.groupValues[3])?.let { return it }
            }
            numericDate.find(text)?.let { match ->
                parsedDate(match.groupValues[1], match.groupValues[2], match.groupValues[3], true)?.let { return it }
            }
        }
        // Pass 2: Dates without year (e.g. PhonePe "September 20 at 2:06 PM" or "20th Sep • 2:06 PM")
        for (line in lines) {
            if (imageHeight > 0 && line.top < imageHeight / 20) continue
            val text = line.text
            monthDay.find(text)?.let { match ->
                parsedDateWithoutYear(match.groupValues[2], match.groupValues[1])?.let { return it }
            }
            dayMonth.find(text)?.let { match ->
                parsedDateWithoutYear(match.groupValues[1], match.groupValues[2])?.let { return it }
            }
        }
        return null
    }

    private fun parsedDate(dayText: String, monthText: String, yearText: String, numericMonth: Boolean = false): Long? {
        val month = if (numericMonth) monthText.toIntOrNull() else
            monthNames.indexOf(monthText.take(3).lowercase(Locale.ENGLISH)).takeIf { it >= 0 }?.plus(1)
        val yearValue = yearText.toIntOrNull() ?: return null
        val year = if (yearText.length == 2) 2000 + yearValue else yearValue
        if (year !in 2000..2100) return null
        return try {
            LocalDate.of(year, month ?: return null, dayText.toInt())
                .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        } catch (_: DateTimeException) {
            null
        }
    }

    private fun parsedDateWithoutYear(dayText: String, monthText: String): Long? {
        val day = dayText.toIntOrNull() ?: return null
        if (day !in 1..31) return null
        val month = monthNames.indexOf(monthText.take(3).lowercase(Locale.ENGLISH)).takeIf { it >= 0 }?.plus(1) ?: return null
        val current = LocalDate.now()
        val year = if (month > current.monthValue + 1) current.year - 1 else current.year
        return try {
            LocalDate.of(year, month, day).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        } catch (_: DateTimeException) {
            null
        }
    }
}
