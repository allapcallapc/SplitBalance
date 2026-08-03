import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';

/// Shows the "update available" prompt and, if the user accepts, walks them
/// through granting the install-unknown-apps permission (if needed) and
/// downloading + installing the update.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  UpdateService updateService,
  UpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context)!;
  final shouldUpdate = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.updateAvailableTitle),
      content: Text(l10n.updateAvailableMessage(update.version)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.updateLater),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.updateNow),
        ),
      ],
    ),
  );
  if (shouldUpdate != true || !context.mounted) return;

  final permissionGranted = await updateService.isInstallPermissionGranted();
  if (!permissionGranted) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.updateAvailableTitle),
        content: Text(l10n.installPermissionRequired),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.updateLater),
          ),
          ElevatedButton(
            onPressed: () async {
              await updateService.openInstallPermissionSettings();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.grantInstallPermission),
          ),
        ],
      ),
    );
    // Whether or not the permission was granted, there's no reliable signal
    // to resume on once we've handed off to system settings - the user just
    // retries "Check for Updates" afterwards.
    return;
  }

  if (!context.mounted) return;
  await _downloadWithProgress(context, updateService, update);
}

Future<void> _downloadWithProgress(
  BuildContext context,
  UpdateService updateService,
  UpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context)!;
  final progress = ValueNotifier<double>(0);

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(l10n.downloadingUpdate),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, child) => LinearProgressIndicator(
          value: value > 0 ? value : null,
        ),
      ),
    ),
  ));

  try {
    await updateService.downloadAndInstall(
      update,
      onProgress: (p) => progress.value = p,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.updateDownloadFailed)),
      );
    }
  } finally {
    progress.dispose();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
