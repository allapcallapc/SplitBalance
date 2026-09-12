package com.splitbalance.app

import android.content.Context
import android.content.SharedPreferences
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever

/**
 * Covers the [GooglePayNotificationListenerService.getRemoveOriginalNotification]/
 * [GooglePayNotificationListenerService.setRemoveOriginalNotification] prefs
 * round-trip directly - [GooglePayNotificationListenerServiceHandleNotificationTest]
 * only exercises the getter indirectly through [GooglePayNotificationListenerService.handleNotification].
 */
class GooglePayNotificationListenerServicePrefsTest {

    private fun contextWithPrefs(prefs: SharedPreferences): Context {
        val context = mock<Context>()
        whenever(
            context.getSharedPreferences(
                eq(GooglePayNotificationListenerService.PREFS_NAME),
                eq(Context.MODE_PRIVATE)
            )
        ).thenReturn(prefs)
        return context
    }

    @Test
    fun `getRemoveOriginalNotification defaults to false when nothing is stored`() {
        val prefs = mock<SharedPreferences>()
        whenever(
            prefs.getBoolean(eq(GooglePayNotificationListenerService.REMOVE_ORIGINAL_NOTIFICATION_KEY), eq(false))
        ).thenReturn(false)

        assertFalse(GooglePayNotificationListenerService.getRemoveOriginalNotification(contextWithPrefs(prefs)))
    }

    @Test
    fun `getRemoveOriginalNotification returns the stored value once enabled`() {
        val prefs = mock<SharedPreferences>()
        whenever(
            prefs.getBoolean(eq(GooglePayNotificationListenerService.REMOVE_ORIGINAL_NOTIFICATION_KEY), eq(false))
        ).thenReturn(true)

        assertTrue(GooglePayNotificationListenerService.getRemoveOriginalNotification(contextWithPrefs(prefs)))
    }

    @Test
    fun `setRemoveOriginalNotification persists the value under the expected key`() {
        val editor = mock<SharedPreferences.Editor>()
        whenever(
            editor.putBoolean(eq(GooglePayNotificationListenerService.REMOVE_ORIGINAL_NOTIFICATION_KEY), eq(true))
        ).thenReturn(editor)
        val prefs = mock<SharedPreferences>()
        whenever(prefs.edit()).thenReturn(editor)

        GooglePayNotificationListenerService.setRemoveOriginalNotification(contextWithPrefs(prefs), true)

        verify(editor).putBoolean(GooglePayNotificationListenerService.REMOVE_ORIGINAL_NOTIFICATION_KEY, true)
        verify(editor).apply()
    }
}
