import 'package:flutter/material.dart';

/// Icon used for categories that don't have one set (or whose stored key
/// isn't recognized by this version of the app).
const IconData defaultCategoryIcon = Icons.category;

/// Maps a serializable icon key (stored on [Category.icon] / the Supabase
/// `categories.icon` column) to the [IconData] used to render it.
///
/// `IconData` itself can't be stored directly (it's not meaningfully
/// serializable - the constant int codepoint isn't stable across icon font
/// versions, and encoding the whole object is overkill), so we persist a
/// small stable string key instead and look it up here. Add new options to
/// this map as needed; keys are never removed since old rows may still
/// reference them.
const Map<String, IconData> categoryIconOptions = {
  'category': Icons.category,
  'restaurant': Icons.restaurant,
  'local_grocery_store': Icons.local_grocery_store,
  'home': Icons.home,
  'directions_car': Icons.directions_car,
  'lightbulb': Icons.lightbulb,
  'water_drop': Icons.water_drop,
  'wifi': Icons.wifi,
  'phone_android': Icons.phone_android,
  'medical_services': Icons.medical_services,
  'school': Icons.school,
  'child_care': Icons.child_care,
  'pets': Icons.pets,
  'fitness_center': Icons.fitness_center,
  'sports_esports': Icons.sports_esports,
  'movie': Icons.movie,
  'coffee': Icons.coffee,
  'local_bar': Icons.local_bar,
  'shopping_cart': Icons.shopping_cart,
  'card_giftcard': Icons.card_giftcard,
  'flight': Icons.flight,
  'hotel': Icons.hotel,
  'build': Icons.build,
  'savings': Icons.savings,
  'receipt_long': Icons.receipt_long,
  'more_horiz': Icons.more_horiz,
};

/// Resolves a stored icon key to its [IconData], falling back to
/// [defaultCategoryIcon] when [key] is null/empty or not a recognized
/// option (e.g. it was written by a newer app version).
IconData resolveCategoryIcon(String? key) {
  if (key == null || key.isEmpty) return defaultCategoryIcon;
  return categoryIconOptions[key] ?? defaultCategoryIcon;
}
