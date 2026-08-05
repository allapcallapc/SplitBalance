package com.splitbalance.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GooglePayNotificationListenerServiceTest {

    @Test
    fun `tap-to-pay transaction with no payment verb is still detected`() {
        // Regression test: Google Wallet's real-world tap-to-pay format ("$X.XX with
        // BANK CARD ..1234") contains no word from PAYMENT_KEYWORDS, so relying on
        // keywords alone silently dropped these notifications.
        val combined = "SAMPLE MERCHANT — \$31.20 with SOME BANK CARD ••1234"

        val amount = GooglePayNotificationListenerService.extractAmount(combined)

        assertEquals(31.20, amount!!, 0.001)
        assertTrue(GooglePayNotificationListenerService.looksLikePayment(combined, amount))
    }

    @Test
    fun `keyword match is still honored when no amount is present`() {
        val combined = "Google Wallet — You sent a payment"

        val amount = GooglePayNotificationListenerService.extractAmount(combined)

        assertNull(amount)
        assertTrue(GooglePayNotificationListenerService.looksLikePayment(combined, amount))
    }

    @Test
    fun `notification with neither an amount nor a keyword is rejected`() {
        val combined = "Google Wallet — Your card was added"

        val amount = GooglePayNotificationListenerService.extractAmount(combined)

        assertNull(amount)
        assertFalse(GooglePayNotificationListenerService.looksLikePayment(combined, amount))
    }

    @Test
    fun `extractAmount handles a plain dollar amount`() {
        assertEquals(12.34, GooglePayNotificationListenerService.extractAmount("\$12.34")!!, 0.001)
    }

    @Test
    fun `extractAmount handles thousands separator with decimal point`() {
        assertEquals(1234.56, GooglePayNotificationListenerService.extractAmount("\$1,234.56")!!, 0.001)
    }

    @Test
    fun `extractAmount handles european comma decimal`() {
        assertEquals(12.34, GooglePayNotificationListenerService.extractAmount("12,34 €")!!, 0.001)
    }

    @Test
    fun `extractAmount returns null when there is no amount`() {
        assertNull(GooglePayNotificationListenerService.extractAmount("Your card was added"))
    }

    @Test
    fun `accepted tradeoff - a non-payment notification with a dollar amount still matches`() {
        // Documents an intentional false-positive: since this is only reached for a
        // watched payment-app package, a balance/promo message with a dollar figure
        // (e.g. "Your Google Wallet balance is $120.00") is treated as a payment too.
        // The cost is low - it only queues a "confirm as bill?" prompt, never creates
        // a bill outright - and it's what lets the real regression case above match.
        val combined = "Google Wallet — Your balance is \$120.00"

        val amount = GooglePayNotificationListenerService.extractAmount(combined)

        assertTrue(GooglePayNotificationListenerService.looksLikePayment(combined, amount))
    }
}
