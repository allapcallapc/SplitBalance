package com.splitbalance.app

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
