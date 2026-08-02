package com.example.splitbalance

import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.splitbalance/notification_access"

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
                else -> result.notImplemented()
            }
        }
    }
}
