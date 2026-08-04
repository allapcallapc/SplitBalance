import 'package:flutter/material.dart';
import '../utils/category_icons.dart';

class Category {
  final String? id;
  final String name;
  // Serializable key into [categoryIconOptions], not a raw IconData (see
  // that file for why). Null means "use the default icon".
  final String? icon;

  Category({this.id, required this.name, this.icon});

  // Resolved icon to render for this category, falling back to
  // [defaultCategoryIcon] when none is set.
  IconData get iconData => resolveCategoryIcon(icon);

  // Convert to a Supabase row payload (no id: assigned by the database)
  Map<String, dynamic> toMap() => {'name': name, 'icon': icon};

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String?,
    );
  }

  // Convert to CSV row
  List<String> toCsvRow() {
    return [name, icon ?? ''];
  }

  // Create from CSV row
  factory Category.fromCsvRow(List<String> row) {
    if (row.isEmpty) {
      throw const FormatException('Category CSV row is empty');
    }
    final icon = row.length > 1 ? row[1].trim() : '';
    return Category(
      name: row[0].trim(),
      icon: icon.isEmpty ? null : icon,
    );
  }

  // CSV header
  static List<String> csvHeader() {
    return ['name', 'icon'];
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
