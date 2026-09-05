import 'package:supabase_flutter/supabase_flutter.dart';

// Pages through [buildQuery] in chunks of [chunkSize] rows (ordered by `id`
// so each page's boundary is stable across requests), folding every row
// into an accumulator via [reduce]. Works around PostgREST's max_rows
// (supabase/config.toml) silently capping an unpaginated .select() at 1000
// rows instead of erroring - shared by AggregatedCalculationService and
// BillsProvider, which both hit this limit summing bill/recovered-amount
// rows, so the paging strategy only needs to change in one place.
Future<T> pageAndReduce<T>({
  required PostgrestFilterBuilder<PostgrestList> Function() buildQuery,
  required T initial,
  required T Function(T accumulator, Map<String, dynamic> row) reduce,
  int chunkSize = 1000,
}) async {
  var accumulator = initial;
  var start = 0;
  while (true) {
    final rows =
        await buildQuery().order('id').range(start, start + chunkSize - 1);
    for (final row in rows) {
      accumulator = reduce(accumulator, row);
    }
    if (rows.length < chunkSize) break;
    start += chunkSize;
  }
  return accumulator;
}
