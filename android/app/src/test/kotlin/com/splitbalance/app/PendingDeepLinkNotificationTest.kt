package com.splitbalance.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Covers [cancelDeepLinkNotification] against a real (Robolectric-shadowed)
 * NotificationManager, since NotificationManagerCompat.cancel() throws against the
 * stub android.jar used elsewhere in this suite. Specifically guards against a
 * regression to cancelAll()-style behavior: tapping into one pending-bill
 * notification (via its body, "Yes", or "See more") must only dismiss that one,
 * leaving any other pending-bill notifications - e.g. two payments detected before
 * either is triaged - untouched.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class PendingDeepLinkNotificationTest {

    private val context = RuntimeEnvironment.getApplication()
    private val manager = context.getSystemService(NotificationManager::class.java)

    private fun postNotification(id: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    GooglePayNotificationListenerService.ALERT_CHANNEL_ID,
                    "Pending bills",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }
        val notification = NotificationCompat.Builder(context, GooglePayNotificationListenerService.ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("New payment detected")
            .build()
        NotificationManagerCompat.from(context).notify(id.hashCode(), notification)
    }

    private fun activeNotificationIds(): List<Int> =
        manager.activeNotifications.map { it.id }

    @Test
    fun `cancels only the notification the deep link came from, leaving other pending-bill notifications alone`() {
        postNotification("first_1700000000000")
        postNotification("second_1700000000500")
        assertEquals(2, activeNotificationIds().size)

        cancelDeepLinkNotification(
            context,
            mapOf("action" to "OPEN_PENDING_PAYMENTS", "id" to "first_1700000000000")
        )

        assertEquals(listOf("second_1700000000500".hashCode()), activeNotificationIds())
    }

    @Test
    fun `null deep link is a no-op, not a crash`() {
        postNotification("solo_123")

        cancelDeepLinkNotification(context, null)

        assertEquals(1, activeNotificationIds().size)
    }

    @Test
    fun `deep link without an id is a no-op`() {
        postNotification("solo_456")

        cancelDeepLinkNotification(context, mapOf("action" to "OPEN_PENDING_PAYMENTS", "id" to null))

        assertEquals(1, activeNotificationIds().size)
    }
}
