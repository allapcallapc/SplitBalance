enum AppThemeMode {
  light,
  dark,
  pink;

  String get displayName {
    switch (this) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.pink:
        return 'Pink';
    }
  }
}

enum AppLanguage {
  english,
  french;

  String get localeCode {
    switch (this) {
      case AppLanguage.english:
        return 'en';
      case AppLanguage.french:
        return 'fr';
    }
  }

  static AppLanguage fromLocaleCode(String? code) {
    switch (code) {
      case 'fr':
        return AppLanguage.french;
      case 'en':
      default:
        return AppLanguage.english;
    }
  }
}

class AppConfig {
  final String? googleDriveFolderId;
  final String person1Name;
  final String person2Name;
  final AppThemeMode themeMode;
  final AppLanguage language;

  AppConfig({
    this.googleDriveFolderId,
    required this.person1Name,
    required this.person2Name,
    this.themeMode = AppThemeMode.light,
    this.language = AppLanguage.english,
  });

  Map<String, dynamic> toJson() {
    return {
      'googleDriveFolderId': googleDriveFolderId,
      'person1Name': person1Name,
      'person2Name': person2Name,
      'themeMode': themeMode.name,
      'language': language.name,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    AppThemeMode themeMode = AppThemeMode.light;
    if (json['themeMode'] != null) {
      try {
        themeMode = AppThemeMode.values.firstWhere(
          (e) => e.name == json['themeMode'],
          orElse: () => AppThemeMode.light,
        );
      } catch (e) {
        themeMode = AppThemeMode.light;
      }
    }

    AppLanguage language = AppLanguage.english;
    if (json['language'] != null) {
      try {
        language = AppLanguage.values.firstWhere(
          (e) => e.name == json['language'],
          orElse: () => AppLanguage.english,
        );
      } catch (e) {
        language = AppLanguage.english;
      }
    }
    
    return AppConfig(
      googleDriveFolderId: json['googleDriveFolderId'] as String?,
      person1Name: json['person1Name'] as String? ?? '',
      person2Name: json['person2Name'] as String? ?? '',
      themeMode: themeMode,
      language: language,
    );
  }

  AppConfig copyWith({
    String? googleDriveFolderId,
    String? person1Name,
    String? person2Name,
    AppThemeMode? themeMode,
    AppLanguage? language,
  }) {
    return AppConfig(
      googleDriveFolderId: googleDriveFolderId ?? this.googleDriveFolderId,
      person1Name: person1Name ?? this.person1Name,
      person2Name: person2Name ?? this.person2Name,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
    );
  }
}
