package com.cash.dash

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class PaymentScreenshotParserTest {
    private fun line(text: String, top: Int, height: Int = 28) = ReceiptLine(text, top, 0, height)
    private fun dateOf(millis: Long?) = millis?.let {
        Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).toLocalDate().toString()
    }

    @Test fun credReceiptUsesHeaderNameAndOrdinalDate() {
        val fields = PaymentScreenshotParser.parse(listOf(
            line("11:04", 10), line("X", 300), line("Xavier Jesu", 360),
            line("₹195", 560, 85), line("SUCCESSFUL", 570),
            line("02:59pm, 20th sep'26", 650), line("Paid via CRED", 740),
            line("AXIS BANK", 900), line("paid to UPI ID", 1600),
            line("m03184284@okicici", 1680)
        ), 2300)
        assertTrue(fields.isPayment)
        assertEquals("Xavier Jesu", fields.title)
        assertEquals(195, fields.amount)
        assertEquals("2026-09-20", dateOf(fields.date))
    }

    @Test fun missingDateNeverDefaultsToToday() {
        val fields = PaymentScreenshotParser.parse(listOf(
            line("Xavier Jesu", 360), line("₹195", 560, 85),
            line("SUCCESSFUL", 570), line("Paid via CRED", 740)
        ), 2300)
        assertNull(fields.date)
    }

    @Test fun upiLabelAndHandleAreNotAName() {
        val fields = PaymentScreenshotParser.parse(listOf(
            line("₹195", 560, 85), line("SUCCESSFUL", 570),
            line("Paid via CRED", 740), line("paid to UPI ID", 1600),
            line("m03184284@okicici", 1680)
        ), 2300)
        assertNull(fields.title)
    }

    @Test fun googlePayPrefersPayeeOverDetailNames() {
        val fields = PaymentScreenshotParser.parse(listOf(
            line("From: MOHAMED AUFIN", 1400), line("21 Sept 2026, 6:19 pm", 950),
            line("To: AMUTHA", 1300), line("Completed", 850),
            line("₹10", 540, 92), line("To Priya", 410)
        ), 2300)
        assertEquals("Priya", fields.title)
        assertEquals(10, fields.amount)
        assertEquals("2026-09-21", dateOf(fields.date))
    }

    @Test fun phonePeReceiptWithWrappedNameAndYearlessDate() {
        val fields = PaymentScreenshotParser.parse(listOf(
            line("11:16", 10),
            line("R", 130),
            line("Raja Gopal Tiffin", 140, 25),
            line("Centre", 185, 25),
            line("Help", 140, 20),
            line("₹1", 400, 60),
            line("Payment Successful", 480, 30),
            line("September 20 at 2:06 PM", 530, 25),
            line("Paid to:", 700),
            line("q432628877@ybl", 750),
            line("UPI Reference ID", 900),
            line("626348265294", 950)
        ), 2300)
        assertTrue(fields.isPayment)
        assertEquals("Raja Gopal Tiffin Centre", fields.title)
        assertEquals(1, fields.amount)
        val expectedYear = java.time.LocalDate.now().year
        assertEquals("$expectedYear-09-20", dateOf(fields.date))
    }

    @Test fun paytmRewardBannerDoesNotVetoReceipt() {
        // Paytm stamps a "Reward expired" promotion over successful transfers; the
        // banner's bare "expired" used to satisfy the failure check and discard the
        // whole receipt before a single field was read.
        val fields = PaymentScreenshotParser.parse(listOf(
            line("11:14", 10),
            line("Paid ₹1", 300, 90),
            line("To Ragini Jagtap", 430),
            line("27 Feb '26, 05:54 pm", 560),
            line("Notes: UPI", 660),
            line("Reward expired", 780),
            line("Services", 950), line("Edit", 950),
            line("Details", 1150), line("Share", 1150),
            line("From: 9080841319@slc", 1300), line("Axis xx3020", 1360),
            line("To: Ragini Jagtap", 1500), line("20221229583742@yesbank", 1570),
            line("UPI Ref ID", 1700), line("605838015256", 1780),
            line("Check balance", 1300)
        ), 2300)
        assertTrue(fields.isPayment)
        assertEquals("Ragini Jagtap", fields.title)
        assertEquals(1, fields.amount)
        assertEquals("2026-02-27", dateOf(fields.date))
    }

    @Test fun randomScreenshotIsNotTurnedIntoAPayment() {
        // The gate extracts even without a success banner, so the other side of that
        // policy has to hold: a random screenshot (settings page, gallery info, chat
        // list) must not arrive on the review form as a payment with a prefilled
        // amount and payee taken from its biggest number and heading.
        val fields = PaymentScreenshotParser.parse(listOf(
            line("Settings", 100),
            line("Battery", 200),
            line("57", 210),
            line("325 photos", 400),
            line("14 Oct 2025", 600),
            line("Storage 128 GB", 700)
        ), 800)
        assertFalse(fields.isPayment)
        assertNull(fields.amount)
        assertNull(fields.amountBox)
        assertNull(fields.title)
        // Dates are still reported for review: a receipt that lost both its success
        // banner and its rupee glyph to OCR has exactly this shape, and it needs the
        // date. The advisory message on the review screen is what marks it unconfirmed.
        assertEquals("2025-10-14", dateOf(fields.date))
    }

    @Test fun missingSuccessBannerStillExtractsFields() {
        // A transaction-details page or a quietly acknowledged transfer never says
        // "Successful". Extraction used to be vetoed wholesale without a success
        // word; per policy only an explicit failure message stops extraction now.
        val fields = PaymentScreenshotParser.parse(listOf(
            line("UPI Ref No: 390750706142", 1890),
            line("₹500", 600, 91),
            line("To: Ragini Jagtap", 430),
            line("14 Oct 2025, 07:55 PM", 1977)
        ), 2359)
        assertEquals("Ragini Jagtap", fields.title)
        assertEquals(500, fields.amount)
        assertEquals("2025-10-14", dateOf(fields.date))
    }

    @Test fun failedEntryInHistoryListDoesNotVetoReceipt() {
        // super.money scrolls a "Past Transactions" list beneath the receipt, and one
        // of those older transfers read "Payment Failed". The failure veto used to
        // scan every line, so a receipt whose own status said "Payment Successful"
        // was discarded because of somebody else's (well, an older) failed payment.
        val fields = PaymentScreenshotParser.parse(listOf(
            line("11:16", 10),
            line("R", 80), line("Raja Gopal Tiffin", 75), line("Centre", 100),
            line("Help", 80),
            line("₹1", 200, 60),
            line("Payment Successful", 237),
            line("September 20 at 2:06 PM", 260),
            line("You have earned 1% cashback", 300),
            line("Paid to:", 345),
            line("q432628877@ybl", 370),
            line("UPI Reference ID", 410),
            line("626348265294", 435),
            line("Payment method", 470),
            line("Axis 3020", 490),
            line("Past Transactions", 660),
            line("September '26", 680),
            line("You Sent", 720), line("₹1", 715), line("20th Sep • 2:06 PM", 745),
            line("Payment Failed", 855)
        ), 980)
        assertTrue(fields.isPayment)
        assertEquals(1, fields.amount)
        assertEquals("2026-09-20", dateOf(fields.date))
    }

    @Test fun failedPaymentIsStillRejected() {
        // The promo filter must not blind the failure check itself: a receipt whose
        // own status line says it failed is not one, banner or no banner.
        val fields = PaymentScreenshotParser.parse(listOf(
            line("Paid ₹1", 300, 90),
            line("To Ragini Jagtap", 430),
            line("Payment Failed", 560),
            line("27 Feb '26, 05:54 pm", 620),
            line("Reward expired", 780)
        ), 2300)
        assertFalse(fields.isPayment)
    }

    @Test fun phonePeReceiptWithDayMonthYearlessDate() {
        val fields = PaymentScreenshotParser.parse(listOf(
            line("Raja Gopal Tiffin", 140, 25),
            line("Centre", 185, 25),
            line("₹1", 400, 60),
            line("Payment Successful", 480, 30),
            line("20th Sep • 2:06 PM", 530, 25),
            line("UPI Reference ID", 900)
        ), 2300)
        assertTrue(fields.isPayment)
        assertEquals("Raja Gopal Tiffin Centre", fields.title)
        assertEquals(1, fields.amount)
        val expectedYear = java.time.LocalDate.now().year
        assertEquals("$expectedYear-09-20", dateOf(fields.date))
    }

    @Test fun fusedPaidAmountKeepsRealLeadingSeven() {
        // ML Kit returned exactly "Paid7,800" for this receipt: the ₹ and the space
        // disappeared. A previous global heuristic then treated the real leading 7 as
        // a malformed rupee glyph and would have converted ₹7,800 into ₹800.
        val fields = PaymentScreenshotParser.parse(listOf(
            line("10:12", 50),
            line("Paid7,800", 490, 78),
            line("To Mohamed Aufin A R", 696, 63),
            line("28 May '25, 10:22 pm", 803, 46),
            line("Notes: Payment from slice", 960),
            line("UPI Ref ID", 2411),
            line("514833942871", 2514)
        ), 3088)
        assertTrue(fields.isPayment)
        assertEquals("Mohamed Aufin A R", fields.title)
        assertEquals(7800, fields.amount)
        assertEquals(AmountEvidence.PAYMENT_LABEL, fields.amountEvidence)
        assertEquals("2025-05-28", dateOf(fields.date))
    }

    @Test fun paytmMoneyReceivedKeepsSenderNameAndDate() {
        // Paytm titles incoming receipts "Money Received". No outgoing verb appears
        // anywhere, so the success gate used to reject the whole screenshot and only
        // the amount — recovered by a separate header scan — survived, with no name
        // and no date.
        val fields = PaymentScreenshotParser.parse(listOf(
            line("Paytm", 119),
            line("Money Received", 446),
            line("10", 600, 91),
            line("Rupees Ten Only", 773),
            line("From: Joohi Sahana M A", 1165),
            line("JA", 1206),
            line("UPI ID: ******5358@ptyes", 1257),
            line("To: Mohamed Aufin A R", 1501),
            line("mohamedaufin64-4@okaxis", 1666),
            line("Bank account linked to", 1736),
            line("UPI Ref No: 390750706142", 1890),
            line("07:55 PM, 14 Oct 2025", 1977),
            line("Paytm", 2254)
        ), 2359)
        assertTrue(fields.isPayment)
        assertEquals("Joohi Sahana M A", fields.title)
        assertEquals(10, fields.amount)
        assertEquals("2025-10-14", dateOf(fields.date))
    }

    @Test fun headerScanFMisreadStillYieldsAmount() {
        // A header re-scan of the same receipt reported the ₹ of ₹10 as F. The glyph
        // misread list has to include it or the recovered amount is thrown away.
        val match = PaymentScreenshotParser.amountInCrop(listOf(
            ReceiptLine("F10", 0, 644, 136, 300)
        ))
        assertEquals(10, match?.value)
        assertEquals(AmountEvidence.GLYPH, match?.evidence)
    }

    @Test fun incomingPaymentDropsFromLabelAndSeparatesTrailingInitials() {
        val fields = PaymentScreenshotParser.parse(listOf(
            line("From SAMPLE PERSON XY", 475, 28),
            line("Paid via CRED", 790),
            line("Completed", 905),
            line("20 Sept 2026, 2:09 pm", 1019),
            line("UPI transaction ID", 1390),
            line("662927703431", 1453),
            line("To: SAMPLE PERSON X Y", 1545),
            line("From: SAMPLE PERSONXY", 1692)
        ), 2560)
        assertTrue(fields.isPayment)
        assertEquals("SAMPLE PERSON X Y", fields.title)
        assertEquals("2026-09-20", dateOf(fields.date))
    }
}
