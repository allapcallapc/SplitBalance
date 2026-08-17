package com.splitbalance.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.splitbalance.app.GooglePayNotificationListenerService.Companion.EXTRA_DEEP_LINK_ID

/**
 * Handles the "No" action on a pending-bill notification: removes the entry
 * from the queue file and dismisses the notification, entirely in the
 * background (no app UI involved).
 */
class PendingPaymentActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_DEEP_LINK_ID) ?: return
        GooglePayNotificationListenerService.removeFromQueue(context, id)
        cancelPendingBillNotification(context, id)
    }
}
