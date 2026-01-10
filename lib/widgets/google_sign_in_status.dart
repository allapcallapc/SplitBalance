import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/config_provider.dart';

/// Widget to display Google Sign-In status in AppBar actions
class GoogleSignInStatus extends StatelessWidget {
  const GoogleSignInStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigProvider>(
      builder: (context, configProvider, child) {
        if (configProvider.isSignedIn) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  color: Colors.green[300],
                  size: 20,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    configProvider.currentUser?.email ?? 'Signed In',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[300],
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cancel,
                color: Colors.grey[400],
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'Not Signed In',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
