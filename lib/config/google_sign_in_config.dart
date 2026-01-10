/// Google Sign-In Configuration
/// 
/// This file loads the Client ID from a local config file that is NOT committed to git.
/// 
/// Setup Instructions:
/// 1. Copy google_sign_in_config.local.dart.example to google_sign_in_config.local.dart
/// 2. Replace YOUR_CLIENT_ID_HERE with your actual Client ID in the local file
/// 3. Update web/index.html with the same Client ID in the meta tag
/// 
/// The local config file (google_sign_in_config.local.dart) is gitignored, 
/// so your Client ID won't be committed to version control.

// Import local config if it exists
// If the file doesn't exist, this will cause an error - that's intentional
// to remind you to create the local config file
import 'google_sign_in_config.local.dart' as local_config;

class GoogleSignInConfig {
  // Load from local config file (gitignored)
  static const String? webClientId = local_config.localWebClientId == 'YOUR_CLIENT_ID_HERE'
      ? null
      : local_config.localWebClientId;
}
