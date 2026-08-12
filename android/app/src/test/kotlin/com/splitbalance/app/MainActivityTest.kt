package com.splitbalance.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MainActivityTest {

    @Test
    fun `intent with no action is not a deep link`() {
        val result = MainActivity.buildPendingDeepLink(
            action = null,
            id = "abc",
            hasAmount = true,
            amount = 12.34,
            details = "Some Merchant"
        )

        assertNull(result)
    }

    @Test
    fun `confirm action carries id, amount and details through`() {
        val result = MainActivity.buildPendingDeepLink(
            action = "confirm",
            id = "abc-123",
            hasAmount = true,
            amount = 31.20,
            details = "SAMPLE MERCHANT"
        )

        assertEquals(
            mapOf(
                "action" to "confirm",
                "id" to "abc-123",
                "amount" to 31.20,
                "details" to "SAMPLE MERCHANT"
            ),
            result
        )
    }

    @Test
    fun `missing amount extra is surfaced as a null amount, not 0-point-0`() {
        val result = MainActivity.buildPendingDeepLink(
            action = "confirm",
            id = "abc-123",
            hasAmount = false,
            amount = 0.0,
            details = null
        )

        assertNull(result?.get("amount"))
        assertEquals("confirm", result?.get("action"))
    }

    @Test
    fun `dismiss action with no id or details still round-trips the action`() {
        val result = MainActivity.buildPendingDeepLink(
            action = "dismiss",
            id = null,
            hasAmount = false,
            amount = 0.0,
            details = null
        )

        assertEquals(
            mapOf(
                "action" to "dismiss",
                "id" to null,
                "amount" to null,
                "details" to null
            ),
            result
        )
    }
}
