import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitbalance/services/tab_index_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabIndexStore', () {
    test('load returns null when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TabIndexStore();

      expect(await store.load(screenCount: 4), isNull);
    });

    test('save then load round-trips the index', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TabIndexStore();

      await store.save(2);

      expect(await store.load(screenCount: 4), 2);
    });

    test('clear removes a previously saved index', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TabIndexStore();
      await store.save(2);

      await store.clear();

      expect(await store.load(screenCount: 4), isNull);
    });

    test('load rejects a negative stored index', () async {
      SharedPreferences.setMockInitialValues({'selected_tab_index': -1});
      final store = TabIndexStore();

      expect(await store.load(screenCount: 4), isNull);
    });

    // Guards against a tab being removed/reordered in a later release
    // leaving a now-out-of-range index on disk from an older install.
    test(
        'load rejects a stored index that is out of range for the '
        'current tab count', () async {
      SharedPreferences.setMockInitialValues({'selected_tab_index': 4});
      final store = TabIndexStore();

      expect(await store.load(screenCount: 4), isNull);
    });

    test('load accepts the last valid index (screenCount - 1)', () async {
      SharedPreferences.setMockInitialValues({'selected_tab_index': 3});
      final store = TabIndexStore();

      expect(await store.load(screenCount: 4), 3);
    });

    test('a later save overwrites an earlier one', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TabIndexStore();
      await store.save(1);

      await store.save(2);

      expect(await store.load(screenCount: 4), 2);
    });
  });
}
