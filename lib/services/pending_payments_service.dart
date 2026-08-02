import 'dart:convert';
import 'dart:io';

import '../models/pending_payment.dart';
import 'notification_access_service.dart';

/// Reads/writes the queue of Google Pay detections the native
/// [NotificationAccessService]-backed listener service appends to.
class PendingPaymentsService {
  final NotificationAccessService _notificationAccessService;

  PendingPaymentsService({NotificationAccessService? notificationAccessService})
      : _notificationAccessService =
            notificationAccessService ?? NotificationAccessService();

  Future<File?> _queueFile() async {
    final path = await _notificationAccessService.getPendingQueueFilePath();
    if (path == null || path.isEmpty) return null;
    return File(path);
  }

  Future<List<PendingPayment>> load() async {
    final file = await _queueFile();
    if (file == null || !await file.exists()) return [];

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PendingPayment.fromJson)
          .toList()
        ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    } catch (e) {
      return [];
    }
  }

  Future<void> remove(String id) async {
    final file = await _queueFile();
    if (file == null || !await file.exists()) return;

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final decoded = jsonDecode(content) as List<dynamic>;
      final remaining = decoded
          .whereType<Map<String, dynamic>>()
          .where((json) => json['id'] != id)
          .toList();
      await file.writeAsString(jsonEncode(remaining));
    } catch (e) {
      // Leave the queue as-is; the item will just reappear next load.
    }
  }
}
