class Category {
  final String? id;
  final String name;

  Category({this.id, required this.name});

  // Convert to a Supabase row payload (no id: assigned by the database)
  Map<String, dynamic> toMap() => {'name': name};

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(id: map['id'] as String, name: map['name'] as String);
  }

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
