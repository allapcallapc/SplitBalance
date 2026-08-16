import 'package:flutter/foundation.dart';

// Lets a screen pushed on top of MainNavigationScreen (e.g.
// CategoryDetailScreen) ask it to switch to a specific bottom-nav tab once
// popped back to - e.g. "show the Bills tab, filtered to this category".
// MainNavigationScreen consumes and clears the request once it acts on it.
class TabNavigationProvider extends ChangeNotifier {
  int? _requestedIndex;

  int? get requestedIndex => _requestedIndex;

  void requestTab(int index) {
    _requestedIndex = index;
    notifyListeners();
  }

  void clear() {
    _requestedIndex = null;
  }
}
