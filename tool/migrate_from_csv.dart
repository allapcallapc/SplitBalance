// One-off migration: reads the old Google Drive CSV exports and writes
// them into the new Supabase schema (households / household_members /
// bills / categories / payment_splits). Run once after both people have
// signed up in the app, then this script can be deleted.
//
// Usage (only one person signed up so far - the other joins later via the
// app's normal invite-code flow; all bill/category/split data imports fine
// either way since it stores names as plain text, not account references):
//   dart run tool/migrate_from_csv.dart \
//     --csv-dir="C:\path\to\csv\folder" \
//     --supabase-url="https://xxxx.supabase.co" \
//     --account-email="a@example.com" \
//     --account-name="Alexis" \
//     [--dry-run]
//
// Usage (both people already signed up - adds both as members in one go):
//   dart run tool/migrate_from_csv.dart \
//     --csv-dir="C:\path\to\csv\folder" \
//     --supabase-url="https://xxxx.supabase.co" \
//     --account-email="a@example.com" \
//     --account-name="Alexis" \
//     --other-email="b@example.com" \
//     [--dry-run]
//
// Requires the SUPABASE_SERVICE_ROLE_KEY environment variable to be set
// (Supabase dashboard > Project Settings > API > service_role secret key).
// That key bypasses row-level security entirely - never commit it, never
// put it in the app itself, only export it locally to run this script:
//   PowerShell: $env:SUPABASE_SERVICE_ROLE_KEY = "..."
//   bash:       export SUPABASE_SERVICE_ROLE_KEY="..."

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/models/category.dart';
import 'package:splitbalance/models/payment_split.dart';

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final eq = arg.indexOf('=');
    if (eq == -1) {
      map[arg.substring(2)] = 'true';
    } else {
      map[arg.substring(2, eq)] = arg.substring(eq + 1);
    }
  }
  return map;
}

List<List<dynamic>> _readCsvRows(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    print('  (not found: $path - skipping)');
    return [];
  }
  final content = file.readAsStringSync();
  if (content.trim().isEmpty) return [];
  final firstLine = content.split(RegExp(r'\r?\n')).first;
  final delimiter = firstLine.contains(';') ? ';' : ',';
  // Must match the file's actual line endings exactly - CsvToListConverter
  // only splits rows on a literal match of `eol`, so passing the wrong one
  // silently collapses the whole file into a single row.
  final eol = content.contains('\r\n') ? '\r\n' : '\n';
  final rows =
      CsvToListConverter(fieldDelimiter: delimiter, eol: eol).convert(content);
  // Drop stray trailing empty rows some CSV writers leave behind.
  rows.removeWhere((row) => row.every((cell) => cell.toString().trim().isEmpty));
  return rows;
}

List<String> _rowToStrings(List<dynamic> row) =>
    row.map((c) => c.toString()).toList();

class SupabaseAdmin {
  SupabaseAdmin(this.baseUrl, this.serviceRoleKey);
  final String baseUrl;
  final String serviceRoleKey;
  final _client = HttpClient();

  Map<String, String> get _headers => {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
        'Content-Type': 'application/json',
      };

  Future<dynamic> _request(String method, String path,
      {Object? body, Map<String, String>? extraHeaders}) async {
    final uri = Uri.parse('$baseUrl$path');
    final request = await _client.openUrl(method, uri);
    _headers.forEach(request.headers.set);
    extraHeaders?.forEach(request.headers.set);
    if (body != null) {
      // request.write() defaults to latin1 encoding unless told otherwise,
      // which corrupts non-ASCII text (accented category names, etc.) -
      // encode to UTF-8 bytes explicitly instead.
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 300) {
      throw Exception(
          '$method $path failed (${response.statusCode}): $responseBody');
    }
    if (responseBody.isEmpty) return null;
    return jsonDecode(responseBody);
  }

  Future<List<Map<String, dynamic>>> listAuthUsers() async {
    final result = await _request('GET', '/auth/v1/admin/users?per_page=200');
    return (result['users'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> insertOne(
      String table, Map<String, dynamic> row) async {
    final result = await _request('POST', '/rest/v1/$table',
        body: row, extraHeaders: {'Prefer': 'return=representation'});
    return (result as List).first as Map<String, dynamic>;
  }

  Future<void> insertMany(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _request('POST', '/rest/v1/$table',
        body: rows, extraHeaders: {'Prefer': 'return=minimal'});
  }

  void close() => _client.close(force: true);
}

void main(List<String> arguments) async {
  final args = _parseArgs(arguments);
  final csvDir = args['csv-dir'];
  final supabaseUrl = args['supabase-url'];
  final accountEmail = args['account-email'];
  final accountName = args['account-name'];
  final otherEmail = args['other-email']; // optional
  final dryRun = args['dry-run'] == 'true';
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];

  if (csvDir == null ||
      supabaseUrl == null ||
      accountEmail == null ||
      accountName == null) {
    print('Usage: dart run tool/migrate_from_csv.dart '
        '--csv-dir=<path> --supabase-url=<url> '
        '--account-email=<email> --account-name=<"Alexis" or "Lorianne"> '
        '[--other-email=<email>] [--dry-run]');
    exit(1);
  }
  if (!dryRun && (serviceRoleKey == null || serviceRoleKey.isEmpty)) {
    print('Set the SUPABASE_SERVICE_ROLE_KEY environment variable first '
        '(Supabase dashboard > Project Settings > API > service_role).');
    exit(1);
  }

  final sep = Platform.pathSeparator;
  final billsPath = '$csvDir$sep' 'bills.csv';
  final splitsPath = '$csvDir$sep' 'payment_splits.csv';
  final categoriesPath = '$csvDir$sep' 'categories.csv';
  final personNamesPath = '$csvDir$sep' 'person_names.csv';

  print('Reading CSVs from $csvDir ...');

  // --- Categories (deduped case-insensitively, matching the DB's unique
  // index on (household_id, lower(name))) ---
  final categoryRows = _readCsvRows(categoriesPath);
  final categories = <Category>[];
  final seenCategoryNames = <String>{};
  for (final raw in categoryRows) {
    final row = _rowToStrings(raw);
    try {
      final category = Category.fromCsvRow(row);
      if (category.name.toLowerCase() == 'name') continue; // header row
      final key = category.name.toLowerCase();
      if (!seenCategoryNames.add(key)) {
        print('  Skipping duplicate category "${category.name}"');
        continue;
      }
      categories.add(category);
    } catch (e) {
      print('  Skipping unparseable category row $row: $e');
    }
  }
  print('Parsed ${categories.length} categories.');

  // --- Bills ---
  final billRows = _readCsvRows(billsPath);
  final bills = <Bill>[];
  for (final raw in billRows) {
    final row = _rowToStrings(raw);
    try {
      bills.add(Bill.fromCsvRow(row));
    } catch (e) {
      print('  Skipping row (likely the header) in bills.csv: $row ($e)');
    }
  }
  print('Parsed ${bills.length} bills.');

  // --- Payment splits ---
  final splitRows = _readCsvRows(splitsPath);
  final splits = <PaymentSplit>[];
  for (final raw in splitRows) {
    final row = _rowToStrings(raw);
    try {
      splits.add(PaymentSplit.fromCsvRow(row));
    } catch (e) {
      print(
          '  Skipping row (likely the header, or invalid) in payment_splits.csv: $row ($e)');
    }
  }
  final persistableSplits = splits.where((s) => s.category != 'all').toList();
  print('Parsed ${splits.length} payment splits '
      '(${splits.length - persistableSplits.length} "all"-category rows will be '
      'skipped - those were always UI-only and never persisted).');

  // --- Person names ---
  final personNameRows = _readCsvRows(personNamesPath);
  String person1Name = '';
  String person2Name = '';
  for (final raw in personNameRows) {
    final row = _rowToStrings(raw);
    if (row.isEmpty) continue;
    if (row[0].trim().toLowerCase() == 'person1name') continue; // header
    person1Name = row.isNotEmpty ? row[0].trim() : '';
    person2Name = row.length > 1 ? row[1].trim() : '';
    break;
  }
  print('Person names: "$person1Name", "$person2Name"');

  // Figure out which CSV name belongs to --account-email, and (if there is
  // one) which name is left for --other-email.
  String myName;
  String? otherName;
  if (accountName.toLowerCase() == person1Name.toLowerCase()) {
    myName = person1Name;
    otherName = person2Name;
  } else if (accountName.toLowerCase() == person2Name.toLowerCase()) {
    myName = person2Name;
    otherName = person1Name;
  } else {
    print('--account-name "$accountName" does not match either name in '
        'person_names.csv ("$person1Name" / "$person2Name"). Check spelling.');
    exit(1);
  }

  if (dryRun) {
    print('\n--dry-run: nothing was written to Supabase.');
    print('Would attach to (or create) a household with:');
    print('  $accountEmail -> "$myName"');
    if (otherEmail != null) {
      print('  $otherEmail -> "$otherName"');
    } else {
      print('  (no second account yet - "$otherName" joins later via invite code)');
    }
    print('Would insert ${categories.length} categories, ${bills.length} bills, '
        '${persistableSplits.length} payment splits.');
    return;
  }

  final admin = SupabaseAdmin(supabaseUrl, serviceRoleKey!);
  try {
    print('\nLooking up accounts by email ...');
    final users = await admin.listAuthUsers();
    String? findId(String email) {
      for (final u in users) {
        if ((u['email'] as String?)?.toLowerCase() == email.toLowerCase()) {
          return u['id'] as String;
        }
      }
      return null;
    }

    final myId = findId(accountEmail);
    if (myId == null) {
      print('Could not find an account for $accountEmail. Make sure you\'ve '
          'signed up (and confirmed your email) in the app first, then '
          're-run this script.');
      exit(1);
    }
    String? otherId;
    if (otherEmail != null) {
      otherId = findId(otherEmail);
      if (otherId == null) {
        print('Could not find an account for $otherEmail. Either leave '
            '--other-email off (they can join later via invite code), or '
            'have them sign up first and re-run.');
        exit(1);
      }
    }
    print('Found account: $accountEmail -> $myId'
        '${otherId != null ? ', $otherEmail -> $otherId' : ''}');

    print('\nChecking for an existing household for this account ...');
    final existingMembership = await admin._request(
        'GET', '/rest/v1/household_members?user_id=eq.$myId&select=household_id');
    String householdId;
    if ((existingMembership as List).isNotEmpty) {
      householdId = existingMembership.first['household_id'] as String;
      print('Found existing household $householdId (already created via the '
          'app) - importing data into it.');
    } else {
      final household = await admin.insertOne('households', {});
      householdId = household['id'] as String;
      print('Created household $householdId '
          '(invite code: ${household['invite_code']}).');
      await admin.insertMany('household_members', [
        {
          'household_id': householdId,
          'user_id': myId,
          'person_name': myName,
        },
      ]);
      print('Added $accountEmail as "$myName".');
    }

    if (otherId != null) {
      final alreadyMember = await admin._request('GET',
          '/rest/v1/household_members?user_id=eq.$otherId&household_id=eq.$householdId&select=user_id');
      if ((alreadyMember as List).isEmpty) {
        await admin.insertMany('household_members', [
          {
            'household_id': householdId,
            'user_id': otherId,
            'person_name': otherName,
          },
        ]);
        print('Added $otherEmail as "$otherName".');
      } else {
        print('$otherEmail is already a member of this household.');
      }
    } else {
      print('No --other-email given - "$otherName" can join later in the '
          'app using this household\'s invite code (shown on the Config '
          'screen once signed in as $accountEmail).');
    }

    if (categories.isNotEmpty) {
      await admin.insertMany('categories', [
        for (final c in categories) {...c.toMap(), 'household_id': householdId}
      ]);
      print('Inserted ${categories.length} categories.');
    }

    if (bills.isNotEmpty) {
      await admin.insertMany('bills', [
        for (final b in bills) {...b.toMap(), 'household_id': householdId}
      ]);
      print('Inserted ${bills.length} bills.');
    }

    if (persistableSplits.isNotEmpty) {
      await admin.insertMany('payment_splits', [
        for (final s in persistableSplits)
          {...s.toMap(), 'household_id': householdId}
      ]);
      print('Inserted ${persistableSplits.length} payment splits.');
    }

    print('\nDone. Sign in as either account in the app - the household and '
        'its data should already be there.');
  } finally {
    admin.close();
  }
}
