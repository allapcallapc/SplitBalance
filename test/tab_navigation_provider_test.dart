import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/providers/tab_navigation_provider.dart';

void main() {
  group('TabNavigationProvider', () {
    test('starts with no requested tab', () {
      final provider = TabNavigationProvider();
      expect(provider.requestedIndex, isNull);
    });

    test('requestTab stores the index and notifies listeners', () {
      final provider = TabNavigationProvider();
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.requestTab(0);

      expect(provider.requestedIndex, 0);
      expect(notifyCount, 1);
    });

    test('requestTab overwrites a previous unconsumed request', () {
      final provider = TabNavigationProvider();

      provider.requestTab(2);
      provider.requestTab(0);

      expect(provider.requestedIndex, 0);
    });

    test('clear resets the requested index without notifying', () {
      final provider = TabNavigationProvider();
      provider.requestTab(1);
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.clear();

      expect(provider.requestedIndex, isNull);
      expect(notifyCount, 0);
    });
  });
}
