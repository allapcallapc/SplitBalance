import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/pending_payments_provider.dart';

/// Settings-screen section for the Android Google Pay notification listener:
/// shows whether notification access is granted, a button to grant it, and
/// an editable list of watched app package names. Renders nothing on
/// unsupported platforms (web).
class GooglePayDetectionSection extends StatefulWidget {
  const GooglePayDetectionSection({super.key});

  @override
  State<GooglePayDetectionSection> createState() =>
      _GooglePayDetectionSectionState();
}

class _GooglePayDetectionSectionState extends State<GooglePayDetectionSection>
    with WidgetsBindingObserver {
  bool? _notificationAccessGranted;
  List<String> _watchedPackages = [];
  bool _loaded = false;
  final _newPackageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _newPackageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh permission status after returning from system settings.
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    final provider = context.read<PendingPaymentsProvider>();
    if (!provider.isSupported) return;

    final granted = await provider.isNotificationAccessGranted();
    final packages = await provider.getWatchedPackages();
    if (granted) {
      // Fire-and-forget: only relevant on Android 13+, no-op otherwise.
      unawaited(provider.requestNotificationPermissionIfNeeded());
    }
    if (mounted) {
      setState(() {
        _notificationAccessGranted = granted;
        _watchedPackages = packages;
        _loaded = true;
      });
    }
  }

  Future<void> _addPackage() async {
    final name = _newPackageController.text.trim();
    if (name.isEmpty || _watchedPackages.contains(name)) return;

    final updated = [..._watchedPackages, name];
    await context.read<PendingPaymentsProvider>().setWatchedPackages(updated);
    if (mounted) {
      setState(() {
        _watchedPackages = updated;
        _newPackageController.clear();
      });
    }
  }

  Future<void> _removePackage(String name) async {
    final updated = _watchedPackages.where((p) => p != name).toList();
    await context.read<PendingPaymentsProvider>().setWatchedPackages(updated);
    if (mounted) {
      setState(() {
        _watchedPackages = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSupported = context.watch<PendingPaymentsProvider>().isSupported;
    if (!isSupported) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final granted = _notificationAccessGranted ?? false;
    final configProvider = context.watch<ConfigProvider>();
    final person1 = configProvider.config.person1Name;
    final person2 = configProvider.config.person2Name;
    final mePersonName = configProvider.config.mePersonName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 24),
                const SizedBox(width: 12),
                Text(
                  l10n.googlePayDetection,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.googlePayDetectionExplanation,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            if (!_loaded)
              const Center(child: CircularProgressIndicator())
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: granted ? Colors.green[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          granted ? Colors.green[200]! : Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      granted
                          ? Icons.check_circle
                          : Icons.warning_amber_rounded,
                      color: granted ? Colors.green[700] : Colors.orange[700],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        granted
                            ? l10n.notificationAccessGranted
                            : l10n.notificationAccessNotGranted,
                        style: TextStyle(
                          color:
                              granted ? Colors.green[900] : Colors.orange[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!granted) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await context
                        .read<PendingPaymentsProvider>()
                        .openNotificationAccessSettings();
                  },
                  icon: const Icon(Icons.settings),
                  label: Text(l10n.grantNotificationAccess),
                ),
              ],
              if (person1.isNotEmpty && person2.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.whoAreYou,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.whoAreYouHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [person1, person2].map((name) {
                    final selected = name == mePersonName;
                    return ChoiceChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (_) => configProvider.setMePersonName(name),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                l10n.watchedApps,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.watchedAppsHint,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _watchedPackages
                    .map(
                      (package) => Chip(
                        label:
                            Text(package, style: const TextStyle(fontSize: 12)),
                        onDeleted: () => _removePackage(package),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPackageController,
                      decoration: InputDecoration(
                        hintText: l10n.addPackageName,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addPackage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addPackage,
                    icon: const Icon(Icons.add_circle),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
