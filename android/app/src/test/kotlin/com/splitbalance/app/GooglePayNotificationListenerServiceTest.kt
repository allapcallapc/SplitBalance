package com.splitbalance.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GooglePayNotificationListenerServiceTest {

    @Test
    fun `tap-to-pay transaction with no payment verb is still detected`() {
        // Regression test: Google Wallet's real-world tap-to-pay format ("$31.20 with
        // BANK CARD ..1775") contains no word from PAYMENT_KEYWORDS, so relying on
        // keywords alone silently dropped these notifications.
        val combined = "BIRDHOUSE WINGERIE & B — \$31.20 with ECHO REMISES MASTERCARD BNC ••1775"

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
}
