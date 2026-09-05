import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bill.dart';
import '../models/duplicate_bill_group.dart';
import 'postgrest_paging.dart';

// Fetches a narrow projection of every bill row in [householdId] (not full
// Bill rows with recovered-amount totals), for client-side duplicate
// grouping. Injectable so tests can control the household's bill set
// without a real Supabase session.
typedef FetchHouseholdBillRows = Future<List<Map<String, dynamic>>> Function({
  required String householdId,
});

// Fetches bill rows in [householdId] matching [date] + [amount] exactly,
// excluding [excludeId] (the bill being edited, if any).
typedef FetchMatchingBillRows = Future<List<Map<String, dynamic>>> Function({
  required String householdId,
  required DateTime date,
  required double amount,
  String? excludeId,
});

final _dateFormat = DateFormat('yyyy-MM-dd');

// Detects "potential duplicate" bills: two or more bills in the same
// household sharing the same date and amount (GH issue #20). Category,
// payer, and details are deliberately ignored for matching - loose on
// purpose, to start.
class DuplicateBillsService {
  DuplicateBillsService({
    FetchHouseholdBillRows? fetchHouseholdBillRows,
    FetchMatchingBillRows? fetchMatchingBillRows,
  })  : _fetchHouseholdBillRows =
            fetchHouseholdBillRows ?? _defaultFetchHouseholdBillRows,
        _fetchMatchingBillRows =
            fetchMatchingBillRows ?? _defaultFetchMatchingBillRows;

  final FetchHouseholdBillRows _fetchHouseholdBillRows;
  final FetchMatchingBillRows _fetchMatchingBillRows;

  // Paginated via pageAndReduce (see BillsProvider.loadAllBills/
  // AggregatedCalculationService) rather than a plain unpaginated .select(),
  // so a household's full bill history doesn't silently get truncated by
  // PostgREST's max_rows cap.
  static Future<List<Map<String, dynamic>>> _defaultFetchHouseholdBillRows({
    required String householdId,
  }) {
    return pageAndReduce<List<Map<String, dynamic>>>(
      buildQuery: () => Supabase.instance.client
          .from('bills')
          .select('id, date, amount, paid_by, category, details')
          .eq('household_id', householdId),
      initial: [],
      reduce: (rows, row) => rows..add(row),
    );
  }

  static Future<List<Map<String, dynamic>>> _defaultFetchMatchingBillRows({
    required String householdId,
    required DateTime date,
    required double amount,
    String? excludeId,
  }) async {
    var query = Supabase.instance.client
        .from('bills')
        .select()
        .eq('household_id', householdId)
        .eq('date', _dateFormat.format(date))
        .eq('amount', amount);
    if (excludeId != null) {
      query = query.neq('id', excludeId);
    }
    return await query;
  }

  // Every group of 2+ bills in [householdId] sharing the same date+amount,
  // newest-first.
  Future<List<DuplicateBillGroup>> findDuplicateGroups(
      String householdId) async {
    final rows = await _fetchHouseholdBillRows(householdId: householdId);

    final byKey = <String, List<Bill>>{};
    for (final row in rows) {
      final bill = Bill.fromMap(row);
      final key = '${_dateFormat.format(bill.date)}|${bill.amount}';
      byKey.putIfAbsent(key, () => []).add(bill);
    }

    final groups = [
      for (final bills in byKey.values)
        if (bills.length > 1)
          DuplicateBillGroup(
            date: bills.first.date,
            amount: bills.first.amount,
            bills: bills,
          ),
    ];
    groups.sort((a, b) => b.date.compareTo(a.date));
    return groups;
  }

  // Existing bills in [householdId] matching [date]+[amount], excluding
  // [excludeId] (the bill being edited, if any) - used to block Save on the
  // Add/Edit Bill screen behind a confirmation step.
  Future<List<Bill>> findMatches({
    required String householdId,
    required DateTime date,
    required double amount,
    String? excludeId,
  }) async {
    final rows = await _fetchMatchingBillRows(
      householdId: householdId,
      date: date,
      amount: amount,
      excludeId: excludeId,
    );
    return rows.map(Bill.fromMap).toList();
  }
}
