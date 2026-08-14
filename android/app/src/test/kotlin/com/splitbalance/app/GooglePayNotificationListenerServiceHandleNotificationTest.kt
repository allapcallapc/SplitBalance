package com.splitbalance.app

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mockito.kotlin.anyOrNull
import org.mockito.kotlin.doReturn
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.spy
import org.mockito.kotlin.whenever
import java.io.File

/**
 * Exercises [GooglePayNotificationListenerService.handleNotification] via Mockito,
 * standing in for the [Context]/[StatusBarNotification] a real device would supply -
 * this repo otherwise avoids Robolectric (see build.gradle.kts), so this is the
 * lightest-weight way to cover the Context-dependent call site there that
 * [GooglePayNotificationListenerServiceTest]'s pure companion-function tests can't
 * reach. Only the queue-persistence path is verified; showAlertNotification()'s
 * PendingIntent/NotificationCompat calls need a real Android runtime and throw
 * against the stub android.jar used for local unit tests, so that expected failure
 * is caught after asserting the queue write already happened.
 */
class GooglePayNotificationListenerServiceHandleNotificationTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun statusBarNotificationFor(
        packageName: String,
        title: String?,
        text: String?,
        bigText: String?
    ): StatusBarNotification {
        val extras = mock<Bundle>()
        whenever(extras.getCharSequence(eq(Notification.EXTRA_TITLE))).thenReturn(title)
        whenever(extras.getCharSequence(eq(Notification.EXTRA_TEXT))).thenReturn(text)
        whenever(extras.getCharSequence(eq(Notification.EXTRA_BIG_TEXT))).thenReturn(bigText)

        val notification = mock<Notification>()
        whenever(notification.extras).thenReturn(extras)

        val sbn = mock<StatusBarNotification>()
        whenever(sbn.packageName).thenReturn(packageName)
        whenever(sbn.notification).thenReturn(notification)
        whenever(sbn.key).thenReturn("key")
        whenever(sbn.postTime).thenReturn(1_700_000_000_000L)
        return sbn
    }

    private fun serviceWithContext(queueDir: File): GooglePayNotificationListenerService {
        val prefs = mock<SharedPreferences>()
        whenever(prefs.getStringSet(eq(GooglePayNotificationListenerService.WATCHED_PACKAGES_KEY), anyOrNull()))
            .thenReturn(null)

        val context = mock<Context>()
        whenever(
            context.getSharedPreferences(
                eq(GooglePayNotificationListenerService.PREFS_NAME),
                eq(Context.MODE_PRIVATE)
            )
        ).thenReturn(prefs)
        whenever(context.filesDir).thenReturn(queueDir)

        val service = spy(GooglePayNotificationListenerService())
        doReturn(context).whenever(service).getApplicationContext()
        return service
    }

    /**
     * showAlertNotification() (called after the queue write, still inside
     * handleNotification) needs real PendingIntent/NotificationCompat/NotificationManager
     * behavior that the stub android.jar throws on outside Robolectric. That's beyond
     * what this test cares about - the queue write above it already happened by then -
     * so the expected failure is swallowed here instead of chasing it into Robolectric.
     */
    private fun invokeHandleNotification(service: GooglePayNotificationListenerService, sbn: StatusBarNotification) {
        try {
            service.handleNotification(sbn)
        } catch (e: Exception) {
            // Expected past the queue write - see the function doc above.
        }
    }

    @Test
    fun `handleNotification queues a detected payment with the title included in the note`() {
        val queueDir = tempFolder.newFolder()
        val service = serviceWithContext(queueDir)
        val packageName = GooglePayNotificationListenerService.DEFAULT_WATCHED_PACKAGES.first()
        val sbn = statusBarNotificationFor(
            packageName = packageName,
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )

        invokeHandleNotification(service, sbn)

        val queueFile = File(queueDir, GooglePayNotificationListenerService.QUEUE_FILE_NAME)
        val queued = JSONArray(queueFile.readText())
        assertEquals(1, queued.length())
        val entry = queued.getJSONObject(0)
        assertEquals("SAMPLE MERCHANT — \$31.20 with SOME BANK CARD ••1234", entry.getString("rawText"))
        assertEquals(31.20, entry.getDouble("parsedAmount"), 0.001)
    }

    @Test
    fun `handleNotification ignores a package that isn't watched`() {
        val queueDir = tempFolder.newFolder()
        val service = serviceWithContext(queueDir)
        val sbn = statusBarNotificationFor(
            packageName = "com.example.unwatched",
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )

        invokeHandleNotification(service, sbn)

        val queueFile = File(queueDir, GooglePayNotificationListenerService.QUEUE_FILE_NAME)
        assertFalse(queueFile.exists())
    }
}
