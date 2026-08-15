# SplitBalance

SplitBalance is a Flutter web app for managing shared bills with Google Drive storage. The app helps couples or roommates track bills, configure payment splits by date range and category, and automatically calculate who owes whom.

## Features

- **Bill Management**: Store bills with date, amount, who paid, category, and details
- **Category Management**: Create and manage custom categories for organizing bills
- **Payment Splits**: Configure percentage-based payment splits by date range and category
- **Balance Calculation**: Automatically calculate how much each person paid versus what they should have paid
- **Google Drive Integration**: All data is stored in CSV files on your Google Drive

## Prerequisites

- Flutter SDK (version 3.0.0 or higher)
- Dart SDK (version 3.0.0 or higher)
- Google Cloud Console account (for Google Drive API setup)

## Regenerating the app icon

The app icon is generated from `assets/logo.png` using [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons). To update it, replace `assets/logo.png` with a new square image (1024x1024 recommended) and run:

```
flutter pub get
dart run flutter_launcher_icons
```

This regenerates the Android launcher icons under `android/app/src/main/res/mipmap-*` and the web icons/favicon under `web/icons` and `web/favicon.png`, based on the `flutter_launcher_icons` config in `pubspec.yaml`.
