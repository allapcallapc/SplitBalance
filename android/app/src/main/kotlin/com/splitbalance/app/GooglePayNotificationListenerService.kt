package com.splitbalance.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.regex.Pattern

/**
 * Watches for payment notifications from Google Pay / Google Wallet and queues
 * a best-effort parse of each one to [QUEUE_FILE_NAME] for the Flutter app to
 * show as a "confirm as bill?" prompt. Nothing here ever creates a bill directly.
 */
class GooglePayNotificationListenerService : NotificationListenerService() {

    companion object {
        const val PREFS_NAME = "google_pay_listener_prefs"
        const val WATCHED_PACKAGES_KEY = "watched_packages"
        const val QUEUE_FILE_NAME = "pending_google_pay_payments.json"

        const val ALERT_CHANNEL_ID = "pending_bills"
        const val EXTRA_DEEP_LINK_ACTION = "deep_link_action"
        const val EXTRA_DEEP_LINK_ID = "deep_link_id"
        const val EXTRA_DEEP_LINK_AMOUNT = "deep_link_amount"
        const val EXTRA_DEEP_LINK_DETAILS = "deep_link_details"
        const val ACTION_ADD_BILL = "ADD_BILL"
        const val ACTION_OPEN_PENDING_PAYMENTS = "OPEN_PENDING_PAYMENTS"

        // Google Pay's Android package name varies by market: Google Wallet (most
        // markets, post-2022 rebrand) vs. the standalone Google Pay app (e.g. India).
        val DEFAULT_WATCHED_PACKAGES = linkedSetOf(
            "com.google.android.apps.walletnfcrel",
            "com.google.android.apps.nbu.paisa.user"
        )

        private val PAYMENT_KEYWORDS = listOf(
            "paid", "payment", "sent", "purchase", "spent", "transaction", "tap to pay"
        )

        // Matches amounts like "$12.34", "12,34 €", "₹1,234.56", "1234.56"
        private val AMOUNT_PATTERN = Pattern.compile(
            "[\\$€£₹]\\s?\\d{1,3}(?:[.,]\\d{3})*(?:[.,]\\d{2})?|\\d{1,3}(?:[.,]\\d{3})*(?:[.,]\\d{2})?\\s?[\\$€£₹]"
        )

        /**
         * Extracts the first money-looking amount out of [text], or null if none is found.
         * Pure/static so it can be unit tested without an Android runtime.
         */
        internal fun extractAmount(text: String): Double? {
            val matcher = AMOUNT_PATTERN.matcher(text)
            if (!matcher.find()) return null
            val digitsOnly = matcher.group().replace(Regex("[^0-9.,]"), "")

            val normalized = when {
                digitsOnly.contains(',') && digitsOnly.contains('.') ->
                    // Both separators present: the last one wins as the decimal point.
                    if (digitsOnly.lastIndexOf(',') > digitsOnly.lastIndexOf('.')) {
                        digitsOnly.replace(".", "").replace(',', '.')
                    } else {
                        digitsOnly.replace(",", "")
                    }
                digitsOnly.contains(',') ->
                    // Only commas: treat as a decimal separator if exactly 2 digits follow it.
                    if (digitsOnly.length - digitsOnly.lastIndexOf(',') - 1 == 2) {
                        digitsOnly.replace(',', '.')
                    } else {
                        digitsOnly.replace(",", "")
                    }
                else -> digitsOnly
            }

            return normalized.toDoubleOrNull()
        }

        /**
         * Whether a notification's combined title/text should be treated as a payment.
         * Notifications only reach here from a watched payment-app package (see
         * [getWatchedPackages]), so a recognizable money amount is on its own enough of
         * a signal — e.g. Google Wallet's tap-to-pay format ("$31.20 with SOME BANK
         * CARD ••1234") never uses verbs like "paid" or "purchase" but always has an amount.
         * The keyword list catches the remaining cases where a payment is described
         * without an amount attached.
         *
         * This is intentionally permissive: a non-payment notification with a dollar
         * figure (a balance summary, a promo) will also match. That's an accepted
         * tradeoff — this only queues a "confirm as bill?" prompt, it never creates a
         * bill outright — in exchange for not silently dropping real payments.
         */
        internal fun looksLikePayment(combinedText: String, amount: Double?): Boolean {
            if (amount != null) return true
            val lower = combinedText.lowercase(Locale.getDefault())
            return PAYMENT_KEYWORDS.any { lower.contains(it) }
        }

        /**
         * Builds the note text queued for a detection and shown in the alert
         * preview: the notification's title plus body (preferring the expanded
         * [bigText] over the collapsed [text] when both are present). Pure/static
         * so it's unit testable without an Android runtime.
         */
        internal fun buildRawText(title: String, text: String, bigText: String): String {
            val body = if (bigText.isNotBlank()) bigText else text
            return listOf(title, body).filter { it.isNotBlank() }.joinToString(" — ")
        }

        /**
         * Amount + note text parsed from a notification's title/text/bigText, or null
         * if it doesn't look like a payment. Pure/static so the whole detection
         * pipeline is unit testable without an Android runtime - [handleNotification]
         * only adds the Context-dependent bits (watched-package check, queue
         * persistence, alert notification) around this.
         */
        internal data class ParsedPayment(val amount: Double?, val rawText: String)

        internal fun parseNotification(title: String, text: String, bigText: String): ParsedPayment? {
            val combined = listOf(title, text, bigText).filter { it.isNotBlank() }.joinToString(" — ")
            if (combined.isBlank()) return null

            val amount = extractAmount(combined)
            if (!looksLikePayment(combined, amount)) return null

            return ParsedPayment(amount, buildRawText(title, text, bigText))
        }

        fun getWatchedPackages(context: Context): Set<String> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return prefs.getStringSet(WATCHED_PACKAGES_KEY, null) ?: DEFAULT_WATCHED_PACKAGES
        }

        fun setWatchedPackages(context: Context, packages: List<String>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putStringSet(WATCHED_PACKAGES_KEY, packages.toSet()).apply()
        }

        /** Directory + file used for the pending-payments queue; also read from MainActivity. */
        fun queueFile(context: Context): File {
            return File(context.filesDir, QUEUE_FILE_NAME)
        }

        /** Removes the entry with the given [id] from the queue file, if present. */
        @Synchronized
        fun removeFromQueue(context: Context, id: String) {
            removeIdFromQueueFile(queueFile(context), id)
        }

        /**
         * Pure file-based version of [removeFromQueue], split out so it's testable
         * without a real Android [Context].
         */
        internal fun removeIdFromQueueFile(file: File, id: String) {
            if (!file.exists()) return
            try {
                val array = JSONArray(file.readText())
                val remaining = JSONArray()
                for (i in 0 until array.length()) {
                    val entry = array.optJSONObject(i) ?: continue
                    if (entry.optString("id") != id) {
                        remaining.put(entry)
                    }
                }
                file.writeText(remaining.toString())
            } catch (e: Exception) {
                // Leave the queue as-is; the item will just reappear next load.
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        try {
            handleNotification(sbn)
        } catch (e: Exception) {
            // Never let a malformed notification crash the listener service.
        }
    }

    private fun handleNotification(sbn: StatusBarNotification) {
        val watched = getWatchedPackages(applicationContext)
        if (!watched.contains(sbn.packageName)) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        val (amount, rawText) = parseNotification(title, text, bigText) ?: return

        val id = "${sbn.key}_${sbn.postTime}"
        val entry = JSONObject().apply {
            put("id", id)
            put("detectedAt", isoNow())
            put("rawTitle", title)
            put("rawText", rawText)
            put("parsedAmount", amount)
        }

        appendToQueue(entry)
        showAlertNotification(id, amount, rawText)
    }

    private fun isoNow(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(Date())
    }

    @Synchronized
    private fun appendToQueue(entry: JSONObject) {
        val file = queueFile(applicationContext)
        val array = if (file.exists()) {
            try {
                JSONArray(file.readText())
            } catch (e: Exception) {
                JSONArray()
            }
        } else {
            JSONArray()
        }
        array.put(entry)
        file.writeText(array.toString())
    }

    private fun showAlertNotification(id: String, amount: Double?, rawText: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            // Not granted; the in-app pending-payments banner is still the fallback.
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    ALERT_CHANNEL_ID,
                    "Pending bills",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }

        val notificationId = id.hashCode()
        val preview = if (amount != null) "Amount: ${"%.2f".format(Locale.US, amount)}" else rawText

        val yesIntent = deepLinkActivityIntent(ACTION_ADD_BILL, id, amount, rawText)
        val seeMoreIntent = deepLinkActivityIntent(ACTION_OPEN_PENDING_PAYMENTS, id, amount, rawText)
        val noIntent = Intent(this, PendingPaymentActionReceiver::class.java).apply {
            putExtra(EXTRA_DEEP_LINK_ID, id)
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val yesPendingIntent = PendingIntent.getActivity(this, notificationId, yesIntent, flags)
        val seeMorePendingIntent = PendingIntent.getActivity(this, notificationId + 1, seeMoreIntent, flags)
        val noPendingIntent = PendingIntent.getBroadcast(this, notificationId + 2, noIntent, flags)

        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("New payment detected")
            .setContentText(preview)
            .setStyle(NotificationCompat.BigTextStyle().bigText(preview))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(seeMorePendingIntent)
            .addAction(0, "Yes", yesPendingIntent)
            .addAction(0, "No", noPendingIntent)
            .addAction(0, "See more", seeMorePendingIntent)
            .build()

        NotificationManagerCompat.from(this).notify(notificationId, notification)
    }

    private fun deepLinkActivityIntent(action: String, id: String, amount: Double?, rawText: String): Intent {
        return Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_DEEP_LINK_ACTION, action)
            putExtra(EXTRA_DEEP_LINK_ID, id)
            if (amount != null) putExtra(EXTRA_DEEP_LINK_AMOUNT, amount)
            putExtra(EXTRA_DEEP_LINK_DETAILS, rawText)
        }
    }
}
