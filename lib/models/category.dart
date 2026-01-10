class Category {
  final String name;

  Category({required this.name});

  // Convert to CSV row
  List<String> toCsvRow() {
    return [name];
  }

  // Create from CSV row
  factory Category.fromCsvRow(List<String> row) {
    if (row.isEmpty) {
      throw const FormatException('Category CSV row is empty');
    }
    return Category(name: row[0].trim());
  }

  // CSV header
  static List<String> csvHeader() {
    return ['name'];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}
