class AppConfig {
  final String? googleDriveFolderId;
  final String person1Name;
  final String person2Name;

  AppConfig({
    this.googleDriveFolderId,
    required this.person1Name,
    required this.person2Name,
  });

  Map<String, dynamic> toJson() {
    return {
      'googleDriveFolderId': googleDriveFolderId,
      'person1Name': person1Name,
      'person2Name': person2Name,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      googleDriveFolderId: json['googleDriveFolderId'] as String?,
      person1Name: json['person1Name'] as String? ?? '',
      person2Name: json['person2Name'] as String? ?? '',
    );
  }

  AppConfig copyWith({
    String? googleDriveFolderId,
    String? person1Name,
    String? person2Name,
  }) {
    return AppConfig(
      googleDriveFolderId: googleDriveFolderId ?? this.googleDriveFolderId,
      person1Name: person1Name ?? this.person1Name,
      person2Name: person2Name ?? this.person2Name,
    );
  }
}
