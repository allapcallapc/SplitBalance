package com.example.splitbalance

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
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

        val combined = listOf(title, text, bigText).filter { it.isNotBlank() }.joinToString(" — ")
        if (combined.isBlank()) return

        val lower = combined.lowercase(Locale.getDefault())
        val looksLikePayment = PAYMENT_KEYWORDS.any { lower.contains(it) }
        if (!looksLikePayment) return

        val entry = JSONObject().apply {
            put("id", "${sbn.key}_${sbn.postTime}")
            put("detectedAt", isoNow())
            put("rawTitle", title)
            put("rawText", if (bigText.isNotBlank()) bigText else text)
            put("parsedAmount", extractAmount(combined))
        }

        appendToQueue(entry)
    }

    private fun extractAmount(text: String): Double? {
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
}
