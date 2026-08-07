// Exercises ConfigProvider.applyHouseholdMembers - the branching that
// decides whether a household_members query result represents a real
// membership or a stale/invalid cached householdId - without needing a
// real signed-in Supabase session (same rationale as bills_provider_test).

import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/providers/config_provider.dart';

void main() {
  group('ConfigProvider.applyHouseholdMembers', () {
    test('an empty members list resets householdId and person names', () {
      final current = AppConfig(
        householdId: 'stale-household-id',
        person1Name: 'Stale Name',
        person2Name: '',
        themeMode: AppThemeMode.dark,
        language: AppLanguage.french,
        mePersonName: 'Stale Name',
      );

      final result = ConfigProvider.applyHouseholdMembers(
        current,
        'stale-household-id',
        const [],
      );

      // The bogus household id must not survive - this is what stops the
      // invite-code fetch (and its UI retry loop) from hammering a
      // household that doesn't exist for this user/environment.
      expect(result.householdId, isNull);
      expect(result.person1Name, '');
      expect(result.person2Name, '');
      // Device-local prefs are unrelated to household membership and must
      // be preserved across the reset.
      expect(result.themeMode, AppThemeMode.dark);
      expect(result.language, AppLanguage.french);
      expect(result.mePersonName, 'Stale Name');
    });

    test('a single member populates person1Name and leaves person2Name '
        'empty (waiting for the other person to join)', () {
      final current = AppConfig(person1Name: '', person2Name: '');

      final result = ConfigProvider.applyHouseholdMembers(
        current,
        'household-1',
        [
          {'user_id': 'u1', 'person_name': 'Bobby', 'joined_at': '2026-01-01'},
        ],
      );

      expect(result.householdId, 'household-1');
      expect(result.person1Name, 'Bobby');
      expect(result.person2Name, '');
    });

    test('two members populate person1Name/person2Name in list order '
        '(the caller is expected to pass them pre-sorted by joined_at)',
        () {
      final current = AppConfig(person1Name: '', person2Name: '');

      final result = ConfigProvider.applyHouseholdMembers(
        current,
        'household-1',
        [
          {'user_id': 'u1', 'person_name': 'Bobby', 'joined_at': '2026-01-01'},
          {'user_id': 'u2', 'person_name': 'Jane', 'joined_at': '2026-01-02'},
        ],
      );

      expect(result.householdId, 'household-1');
      expect(result.person1Name, 'Bobby');
      expect(result.person2Name, 'Jane');
    });
  });
}
