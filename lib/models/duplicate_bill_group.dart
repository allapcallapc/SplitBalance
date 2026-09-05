import 'bill.dart';

// A set of two or more bills that share the same date and amount within a
// household - see DuplicateBillsService for the matching rule (GH issue #20).
class DuplicateBillGroup {
  final DateTime date;
  final double amount;
  final List<Bill> bills;

  DuplicateBillGroup({
    required this.date,
    required this.amount,
    required this.bills,
  });
}
