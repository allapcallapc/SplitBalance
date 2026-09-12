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
 * lighter-weight than Robolectric for the Context-dependent call site here that
 * [GooglePayNotificationListenerServiceTest]'s pure companion-function tests can't
 * reach. handleNotification()'s Context is passed explicitly precisely so this
 * doesn't need to spy the Service itself - only its plain-mockable arguments. The one
 * path this can't cover - onNotificationPosted()'s applicationContext resolution -
 * is exercised separately in GooglePayNotificationListenerServiceRobolectricTest.
 * [hasPermission] and [postAlert] are stubbed out (rather than left at their real
 * defaults) precisely so these tests can exercise the permission-gated
 * cancel/post logic without the real NotificationManager/PendingIntent calls that
 * throw against the stub android.jar used for local unit tests outside Robolectric.
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

    private fun contextWithQueueDir(
        queueDir: File,
        removeOriginalNotification: Boolean = false
    ): Context {
        val prefs = mock<SharedPreferences>()
        whenever(prefs.getStringSet(eq(GooglePayNotificationListenerService.WATCHED_PACKAGES_KEY), anyOrNull()))
            .thenReturn(null)
        whenever(
            prefs.getBoolean(eq(GooglePayNotificationListenerService.REMOVE_ORIGINAL_NOTIFICATION_KEY), eq(false))
        ).thenReturn(removeOriginalNotification)

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

    private fun invokeHandleNotification(
        sbn: StatusBarNotification,
        context: Context,
        hasPermission: () -> Boolean = { true },
        postAlert: (String, Double?, String) -> Unit = { _, _, _ -> },
        cancelOriginal: (String) -> Unit = {}
    ) {
        GooglePayNotificationListenerService().handleNotification(sbn, context, hasPermission, postAlert, cancelOriginal)
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

    @Test
    fun `handleNotification ignores a watched package whose content isn't a payment`() {
        val queueDir = tempFolder.newFolder()
        val context = contextWithQueueDir(queueDir)
        val packageName = GooglePayNotificationListenerService.DEFAULT_WATCHED_PACKAGES.first()
        val sbn = statusBarNotificationFor(
            packageName = packageName,
            title = "Google Wallet",
            text = "Your card was added",
            bigText = null
        )

        invokeHandleNotification(sbn, context)

        val queueFile = File(queueDir, GooglePayNotificationListenerService.QUEUE_FILE_NAME)
        assertFalse(queueFile.exists())
    }

    @Test
    fun `handleNotification cancels the original notification when the setting is enabled`() {
        val queueDir = tempFolder.newFolder()
        val context = contextWithQueueDir(queueDir, removeOriginalNotification = true)
        val packageName = GooglePayNotificationListenerService.DEFAULT_WATCHED_PACKAGES.first()
        val sbn = statusBarNotificationFor(
            packageName = packageName,
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )
        var cancelledKey: String? = null

        invokeHandleNotification(sbn, context) { key -> cancelledKey = key }

        assertEquals("key", cancelledKey)
    }

    @Test
    fun `handleNotification leaves the original notification alone when the setting is disabled`() {
        val queueDir = tempFolder.newFolder()
        val context = contextWithQueueDir(queueDir, removeOriginalNotification = false)
        val packageName = GooglePayNotificationListenerService.DEFAULT_WATCHED_PACKAGES.first()
        val sbn = statusBarNotificationFor(
            packageName = packageName,
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )
        var cancelCalled = false

        invokeHandleNotification(sbn, context) { cancelCalled = true }

        assertFalse(cancelCalled)
    }

    @Test
    fun `handleNotification neither posts nor cancels when notification permission is denied`() {
        val queueDir = tempFolder.newFolder()
        val context = contextWithQueueDir(queueDir, removeOriginalNotification = true)
        val packageName = GooglePayNotificationListenerService.DEFAULT_WATCHED_PACKAGES.first()
        val sbn = statusBarNotificationFor(
            packageName = packageName,
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )
        var postAlertCalled = false
        var cancelCalled = false

        invokeHandleNotification(
            sbn,
            context,
            hasPermission = { false },
            postAlert = { _, _, _ -> postAlertCalled = true },
            cancelOriginal = { cancelCalled = true }
        )

        assertFalse(postAlertCalled)
        assertFalse(cancelCalled)
    }

    @Test
    fun `handleNotification does not cancel the original notification when posting the alert fails`() {
        val queueDir = tempFolder.newFolder()
        val context = contextWithQueueDir(queueDir, removeOriginalNotification = true)
        val packageName = GooglePayNotificationListenerService.DEFAULT_WATCHED_PACKAGES.first()
        val sbn = statusBarNotificationFor(
            packageName = packageName,
            title = "SAMPLE MERCHANT",
            text = "\$31.20 with SOME BANK CARD ••1234",
            bigText = null
        )
        var cancelCalled = false

        try {
            invokeHandleNotification(
                sbn,
                context,
                postAlert = { _, _, _ -> throw SecurityException("simulated notify() failure") },
                cancelOriginal = { cancelCalled = true }
            )
        } catch (e: SecurityException) {
            // Expected: propagates past handleNotification, same as it would past
            // onNotificationPosted's own try/catch in production.
        }

        assertFalse(cancelCalled)
    }

}
