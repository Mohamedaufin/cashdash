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
}
