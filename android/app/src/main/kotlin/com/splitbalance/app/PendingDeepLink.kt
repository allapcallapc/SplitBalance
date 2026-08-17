package com.splitbalance.app

import android.content.Context
import androidx.core.app.NotificationManagerCompat

/**
 * Pure translation of the deep-link Intent extras set by
 * [GooglePayNotificationListenerService] into the map MainActivity hands to Dart.
 * Returns null when there's no action, i.e. the intent didn't come from tapping a
 * pending-bill notification.
 *
 * Deliberately kept out of MainActivity itself: MainActivity extends FlutterActivity,
 * and referencing anything on that class from a plain JUnit test forces the JVM to
 * link the real Flutter embedding classes, which fails outside an Android/Flutter
 * runtime. A standalone top-level function avoids that entirely.
 */
internal fun buildPendingDeepLink(
    action: String?,
    id: String?,
    hasAmount: Boolean,
    amount: Double,
    details: String?
): Map<String, Any?>? {
    if (action == null) return null
    return mapOf(
        "action" to action,
        "id" to id,
        "amount" to if (hasAmount) amount else null,
        "details" to details
    )
}

/**
 * Dismisses the pending-bill notification a deep link was tapped from, using the
 * same `id.hashCode()` scheme [GooglePayNotificationListenerService.showAlertNotification]
 * posts under. Only "No" (handled by [PendingPaymentActionReceiver]) cancelled its
 * notification before; the notification body and the "Yes"/"See more" actions all
 * launch MainActivity instead, and `Notification.FLAG_AUTO_CANCEL` only dismisses a
 * notification when its content intent fires - not action-button intents - so those
 * were left lingering in the shade. Cancelling by this specific hashed id (rather
 * than `cancelAll()`) means it only ever touches the one notification that was
 * actually tapped, leaving any other pending-bill notifications untouched.
 *
 * Kept out of MainActivity for the same reason as [buildPendingDeepLink]: it takes
 * [Context] explicitly so it's callable from a plain JVM/Robolectric test without
 * linking the Flutter embedding.
 */
internal fun cancelDeepLinkNotification(context: Context, deepLink: Map<String, Any?>?) {
    val id = deepLink?.get("id") as? String ?: return
    NotificationManagerCompat.from(context).cancel(id.hashCode())
}
