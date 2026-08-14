package com.splitbalance.app

import android.service.notification.StatusBarNotification
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Covers the one path [GooglePayNotificationListenerServiceHandleNotificationTest]'s
 * plain Mockito approach can't reach: onNotificationPosted()'s applicationContext
 * resolution. The stub android.jar used for local unit tests can't resolve
 * applicationContext for an unattached Service at all (there's no real Context behind
 * it), so Robolectric - which attaches the service to a real, working shadow
 * Context/Application - is used for just this one test rather than for the whole
 * suite, keeping the heavier Robolectric runtime scoped to where it's actually needed.
 *
 * sdk is pinned below the app's real compileSdk/targetSdk (whatever the installed
 * Flutter version's Android embedding currently targets) since Robolectric only ships
 * shadows up to whatever API level its own release supports - letting it auto-pick
 * from the manifest fails with "Robolectric does not support API level X" the moment
 * the app's target SDK gets ahead of Robolectric's latest supported one.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GooglePayNotificationListenerServiceRobolectricTest {

    @Test
    fun `onNotificationPosted resolves a real applicationContext without throwing`() {
        val service = Robolectric.setupService(GooglePayNotificationListenerService::class.java)

        // An unwatched package is enough to reach and exercise the
        // handleNotification(sbn, applicationContext) call site, then return before
        // touching the notification's extras - no need to build a full Notification.
        val sbn = mock<StatusBarNotification>()
        whenever(sbn.packageName).thenReturn("com.example.unrelated")

        service.onNotificationPosted(sbn)
    }
}
