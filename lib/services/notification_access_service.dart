import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the native `com.splitbalance/notification_access`
/// channel used to control the Android Google Pay notification listener.
/// Every method is a no-op on web/other platforms since the feature is
/// Android-only.
class NotificationAccessService {
  static const MethodChannel _channel =
      MethodChannel('com.splitbalance/notification_access');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> isNotificationAccessGranted() async {
    if (!isSupported) return false;
    try {
      final granted =
          await _channel.invokeMethod<bool>('isNotificationAccessGranted');
      return granted ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('openNotificationAccessSettings');
    } catch (e) {
      // Ignore - user will see nothing happen and can retry.
    }
  }

  Future<List<String>> getWatchedPackages() async {
    if (!isSupported) return [];
    try {
      final result =
          await _channel.invokeMethod<List<Object?>>('getWatchedPackages');
      return result?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<void> setWatchedPackages(List<String> packages) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setWatchedPackages', packages);
    } catch (e) {
      // Ignore - settings screen will show the previous state on next load.
    }
  }

  Future<String?> getPendingQueueFilePath() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('getPendingQueueFilePath');
    } catch (e) {
      return null;
    }
  }

  Future<void> requestNotificationPermissionIfNeeded() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('requestNotificationPermissionIfNeeded');
    } catch (e) {
      // Ignore - worst case the alert notification just won't show; the
      // in-app pending-payments banner is still the fallback.
    }
  }

  /// Returns the deep-link extras from a "pending bill" notification action
  /// (`action`, `id`, `amount`, `details`), or null if none is pending.
  Future<Map<String, dynamic>?> getPendingDeepLink() async {
    if (!isSupported) return null;
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('getPendingDeepLink');
      if (result == null || result['action'] == null) return null;
      return result;
    } catch (e) {
      return null;
    }
  }

  Future<void> clearPendingDeepLink() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('clearPendingDeepLink');
    } catch (e) {
      // Ignore - worst case the same deep link is handled twice.
    }
  }
}
