class PendingPayment {
  final String id;
  final DateTime detectedAt;
  final String rawTitle;
  final String rawText;
  final double? parsedAmount;

  PendingPayment({
    required this.id,
    required this.detectedAt,
    required this.rawTitle,
    required this.rawText,
    this.parsedAmount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'detectedAt': detectedAt.toIso8601String(),
      'rawTitle': rawTitle,
      'rawText': rawText,
      'parsedAmount': parsedAmount,
    };
  }

  factory PendingPayment.fromJson(Map<String, dynamic> json) {
    return PendingPayment(
      id: json['id'] as String,
      detectedAt: DateTime.tryParse(json['detectedAt'] as String? ?? '') ??
          DateTime.now(),
      rawTitle: json['rawTitle'] as String? ?? '',
      rawText: json['rawText'] as String? ?? '',
      parsedAmount: (json['parsedAmount'] as num?)?.toDouble(),
    );
  }
}
