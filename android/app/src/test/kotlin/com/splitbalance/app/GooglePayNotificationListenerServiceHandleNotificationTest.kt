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
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import java.io.File

/**
 * Exercises [GooglePayNotificationListenerService.handleNotification] via Mockito,
 * standing in for the [Context]/[StatusBarNotification] a real device would supply -
 * this repo otherwise avoids Robolectric (see build.gradle.kts), so this is the
 * lightest-weight way to cover the Context-dependent call site there that
 * [GooglePayNotificationListenerServiceTest]'s pure companion-function tests can't
 * reach. handleNotification()'s Context is passed explicitly (it defaults to
 * applicationContext for the real onNotificationPosted call site) precisely so this
 * doesn't need to spy the Service itself - only its plain-mockable arguments.
 * Only the queue-persistence path is verified; showAlertNotification()'s
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
        // Notification.extras is a plain public field with no matching getter, so
        // Kotlin property syntax (notification.extras) reads it directly rather than
        // calling a mockable method - Mockito never sees an invocation to stub in that
        // case (MissingMethodInvocationException). Set the field via reflection instead.
        Notification::class.java.getField("extras").set(notification, extras)

        val sbn = mock<StatusBarNotification>()
        whenever(sbn.packageName).thenReturn(packageName)
        whenever(sbn.notification).thenReturn(notification)
        whenever(sbn.key).thenReturn("key")
        whenever(sbn.postTime).thenReturn(1_700_000_000_000L)
        return sbn
    }

    private fun contextWithQueueDir(queueDir: File): Context {
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
        return context
    }

    /**
     * showAlertNotification() (called after the queue write, still inside
     * handleNotification) needs real PendingIntent/NotificationCompat/NotificationManager
     * behavior that the stub android.jar throws on outside Robolectric. That's beyond
     * what this test cares about - the queue write above it already happened by then -
     * so the expected failure is swallowed here instead of chasing it into Robolectric.
     */
    private fun invokeHandleNotification(sbn: StatusBarNotification, context: Context) {
        try {
            GooglePayNotificationListenerService().handleNotification(sbn, context)
        } catch (e: Exception) {
            // Expected past the queue write - see the function doc above.
        }
    }

    @Test
    fun `handleNotification queues a detected payment with the title included in the note`() {
        val queueDir = tempFolder.newFolder()
        val context = contextWithQueueDir(queueDir)
        val packageName = GooglePayNotificationListenerService.DEFAULT_WATCHED_PACKAGES.first()
        val sbn = statusBarNotificationFor(
            packageName = packageName,
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )

        invokeHandleNotification(sbn, context)

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
        val context = contextWithQueueDir(queueDir)
        val sbn = statusBarNotificationFor(
            packageName = "com.example.unwatched",
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )

        invokeHandleNotification(sbn, context)

        val queueFile = File(queueDir, GooglePayNotificationListenerService.QUEUE_FILE_NAME)
        assertFalse(queueFile.exists())
    }
}
