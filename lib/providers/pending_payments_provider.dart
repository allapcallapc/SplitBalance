import 'package:flutter/foundation.dart';
import '../models/pending_payment.dart';
import '../services/notification_access_service.dart';
import '../services/pending_payments_service.dart';

class PendingPaymentsProvider with ChangeNotifier {
  final PendingPaymentsService _service;
  final NotificationAccessService _notificationAccessService;

  List<PendingPayment> _pendingPayments = [];
  bool _isLoading = false;

  PendingPaymentsProvider({
    PendingPaymentsService? service,
    NotificationAccessService? notificationAccessService,
  })  : _notificationAccessService =
            notificationAccessService ?? NotificationAccessService(),
        _service = service ??
            PendingPaymentsService(
                notificationAccessService: notificationAccessService);

  List<PendingPayment> get pendingPayments =>
      List.unmodifiable(_pendingPayments);
  bool get isLoading => _isLoading;
  bool get isSupported => NotificationAccessService.isSupported;

  Future<void> loadPending() async {
    if (!isSupported) return;

    _isLoading = true;
    notifyListeners();

    try {
      _pendingPayments = await _service.load();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> dismiss(String id) async {
    await _service.remove(id);
    _pendingPayments = _pendingPayments.where((p) => p.id != id).toList();
    notifyListeners();
  }

  Future<bool> isNotificationAccessGranted() {
    return _notificationAccessService.isNotificationAccessGranted();
  }

  Future<void> openNotificationAccessSettings() {
    return _notificationAccessService.openNotificationAccessSettings();
  }

  Future<List<String>> getWatchedPackages() {
    return _notificationAccessService.getWatchedPackages();
  }

  Future<void> setWatchedPackages(List<String> packages) {
    return _notificationAccessService.setWatchedPackages(packages);
  }

  Future<void> requestNotificationPermissionIfNeeded() {
    return _notificationAccessService.requestNotificationPermissionIfNeeded();
  }

  Future<Map<String, dynamic>?> getPendingDeepLink() {
    return _notificationAccessService.getPendingDeepLink();
  }

  Future<void> clearPendingDeepLink() {
    return _notificationAccessService.clearPendingDeepLink();
  }
}
