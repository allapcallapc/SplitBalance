import 'package:shared_preferences/shared_preferences.dart';

/// Persists the selected bottom-nav tab across refreshes/restarts (GH issue
/// #59), so MainNavigationScreen can restore it once a session settles
/// instead of always landing on Bills.
class TabIndexStore {
  static const _storageKey = 'selected_tab_index';

  /// Returns the persisted index, or null if nothing is stored or the
  /// stored value is out of range for [screenCount] (e.g. a tab was
  /// removed/reordered in a later release). Callers should treat null the
  /// same as "nothing persisted" and fall back to their own default.
  Future<int?> load({required int screenCount}) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_storageKey);
    if (stored == null || stored < 0 || stored >= screenCount) return null;
    return stored;
  }

  Future<void> save(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, index);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
