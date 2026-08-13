package com.splitbalance.app

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Covers the effect of [PendingPaymentActionReceiver]'s "No" action - removing the
 * tapped entry from the pending-payments queue file - via
 * [GooglePayNotificationListenerService.removeIdFromQueueFile], the pure,
 * Context-free core the receiver delegates to. The receiver itself is a three-line
 * BroadcastReceiver wrapper around this plus a NotificationManagerCompat.cancel()
 * call, both of which need a real Android Context to exercise.
 */
class PendingPaymentActionReceiverTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun queueFileWith(vararg ids: String): File {
        val array = JSONArray()
        for (id in ids) {
            array.put(JSONObject().put("id", id).put("amount", 12.34))
        }
        val file = tempFolder.newFile("pending_google_pay_payments.json")
        file.writeText(array.toString())
        return file
    }

    private fun idsIn(file: File): List<String> {
        val array = JSONArray(file.readText())
        return (0 until array.length()).map { array.getJSONObject(it).getString("id") }
    }

    @Test
    fun `removes only the matching entry, keeping the rest of the queue`() {
        val file = queueFileWith("a", "b", "c")

        GooglePayNotificationListenerService.removeIdFromQueueFile(file, "b")

        assertEquals(listOf("a", "c"), idsIn(file))
    }

    @Test
    fun `removing the only entry leaves an empty queue`() {
        val file = queueFileWith("solo")

        GooglePayNotificationListenerService.removeIdFromQueueFile(file, "solo")

        assertEquals(emptyList<String>(), idsIn(file))
    }

    @Test
    fun `removing an id that isn't queued leaves the queue untouched`() {
        val file = queueFileWith("a", "b")

        GooglePayNotificationListenerService.removeIdFromQueueFile(file, "does-not-exist")

        assertEquals(listOf("a", "b"), idsIn(file))
    }

    @Test
    fun `missing queue file is a no-op, not a crash`() {
        val file = File(tempFolder.root, "does-not-exist.json")

        GooglePayNotificationListenerService.removeIdFromQueueFile(file, "any-id")

        assertFalse(file.exists())
    }

    @Test
    fun `malformed queue file is left as-is rather than losing pending entries`() {
        val file = tempFolder.newFile("pending_google_pay_payments.json")
        file.writeText("not valid json")

        GooglePayNotificationListenerService.removeIdFromQueueFile(file, "any-id")

        assertEquals("not valid json", file.readText())
    }
}
