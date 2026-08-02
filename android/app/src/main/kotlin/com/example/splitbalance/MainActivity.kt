package com.example.splitbalance

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.splitbalance/notification_access"
    private var pendingDeepLink: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractDeepLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractDeepLink(intent)
    }

    private fun extractDeepLink(intent: Intent?) {
        val action = intent?.getStringExtra(GooglePayNotificationListenerService.EXTRA_DEEP_LINK_ACTION) ?: return
        val amount = if (intent.hasExtra(GooglePayNotificationListenerService.EXTRA_DEEP_LINK_AMOUNT)) {
            intent.getDoubleExtra(GooglePayNotificationListenerService.EXTRA_DEEP_LINK_AMOUNT, 0.0)
        } else {
            null
        }
        pendingDeepLink = mapOf(
            "action" to action,
            "id" to intent.getStringExtra(GooglePayNotificationListenerService.EXTRA_DEEP_LINK_ID),
            "amount" to amount,
            "details" to intent.getStringExtra(GooglePayNotificationListenerService.EXTRA_DEEP_LINK_DETAILS)
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" -> {
                    val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(this)
                    result.success(enabledPackages.contains(packageName))
                }
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "getWatchedPackages" -> {
                    result.success(GooglePayNotificationListenerService.getWatchedPackages(applicationContext).toList())
                }
                "setWatchedPackages" -> {
                    @Suppress("UNCHECKED_CAST")
                    val packages = call.arguments as? List<String> ?: emptyList()
                    GooglePayNotificationListenerService.setWatchedPackages(applicationContext, packages)
                    result.success(null)
                }
                "getPendingQueueFilePath" -> {
                    result.success(GooglePayNotificationListenerService.queueFile(applicationContext).absolutePath)
                }
                "requestNotificationPermissionIfNeeded" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                    }
                    result.success(null)
                }
                "getPendingDeepLink" -> {
                    result.success(pendingDeepLink)
                }
                "clearPendingDeepLink" -> {
                    pendingDeepLink = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
