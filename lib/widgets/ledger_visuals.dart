import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

// Colors used throughout the summary screen and its detail screens to
// distinguish each person's paid amounts.
class PersonColors {
  static final Color person1 = Colors.teal[600]!;
  static final Color person2 = Colors.orange[700]!;
}

// A colored dot followed by a label - shared by the person legend, the
// per-row paid amounts, and the detail screens' current-period summaries.
class DotLabel extends StatelessWidget {
  const DotLabel(
    this.color,
    this.text, {
    super.key,
    required this.dotSize,
    required this.gap,
    required this.textStyle,
  });

  final Color color;
  final String text;
  final double dotSize;
  final double gap;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: gap),
        Text(text, style: textStyle),
      ],
    );
  }
}

// A single icon+text line stating the balance verdict (who overpaid,
// settled, or no split set).
class VerdictLine extends StatelessWidget {
  const VerdictLine(this.icon, this.text, this.color, {super.key});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// A horizontal bar showing person1's paid amount as a proportion of the
// total, with a tick marking where their fair share would land.
class ProportionalBar extends StatelessWidget {
  const ProportionalBar({
    super.key,
    required this.person1Fraction,
    required this.tickFraction,
  });

  final double person1Fraction;
  final double tickFraction;

  static const double height = 14.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final tickColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.35);

    // Flex must be a positive integer, so express the split in thousandths
    // and keep both sides >= 1 even when one person paid nothing.
    final int rawFlex = (person1Fraction * 1000).round();
    final int person1Flex = math.min(999, math.max(1, rawFlex));
    final int person2Flex = 1000 - person1Flex;

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: trackColor),
            Row(
              children: [
                Expanded(
                    flex: person1Flex,
                    child: Container(color: PersonColors.person1)),
                Expanded(
                    flex: person2Flex,
                    child: Container(color: PersonColors.person2)),
              ],
            ),
            Align(
              alignment: Alignment(tickFraction * 2 - 1, 0),
              child: Container(
                width: 2,
                height: height,
                color: tickColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The current-period summary block shared by a summary-screen ledger row
// and the detail screens: label/icon + total, the proportional bar, each
// person's raw paid amount, and the one-line verdict naming whoever
// overpaid. Pulled out of SummaryScreen so CategoryDetailScreen and
// TotalDetailScreen can reuse the exact same styling instead of
// re-implementing it.
class LedgerSummaryCard extends StatelessWidget {
  const LedgerSummaryCard({
    super.key,
    required this.label,
    this.icon,
    required this.total,
    required this.person1Paid,
    required this.person1Expected,
    required this.person2Paid,
    required this.person2Expected,
    required this.currencyFormat,
    required this.person1Name,
    required this.person2Name,
    this.isTotalRow = false,
  });

  final String label;
  final IconData? icon;
  final double total;
  final double person1Paid;
  final double person1Expected;
  final double person2Paid;
  final double person2Expected;
  final NumberFormat currencyFormat;
  final String person1Name;
  final String person2Name;
  final bool isTotalRow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // A category can have paid amounts with no matching payment split (see
    // CalculationService), in which case expected stays 0 for both people -
    // there's no fair-share basis to compare against, so no verdict should
    // be declared.
    final expectedTotal = person1Expected + person2Expected;
    final hasExpectedShare = expectedTotal > 0.01;

    const epsilon = 0.01;
    final difference = person1Paid - person1Expected;
    final isBalanced = difference.abs() < epsilon;
    final person1Overpaid = difference >= epsilon;

    final double person1Fraction =
        total > 0.01 ? math.min(1.0, math.max(0.0, person1Paid / total)) : 0.5;
    final double tickFraction = hasExpectedShare && total > 0.01
        ? math.min(1.0, math.max(0.0, person1Expected / total))
        : 0.5;

    final Widget verdict;
    if (!hasExpectedShare) {
      verdict = VerdictLine(Icons.remove, l10n.noSplitSet, Colors.grey[500]!);
    } else if (isBalanced) {
      verdict = VerdictLine(Icons.check, l10n.settled, Colors.grey[600]!);
    } else {
      verdict = VerdictLine(
        Icons.arrow_upward,
        '${person1Overpaid ? person1Name : person2Name} '
        '${l10n.overpaid} '
        '${currencyFormat.format(difference.abs())}',
        person1Overpaid ? PersonColors.person1 : PersonColors.person2,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isTotalRow ? FontWeight.bold : FontWeight.w600,
                  fontSize: isTotalRow ? 15 : 14,
                ),
              ),
            ),
            Text(
              currencyFormat.format(total),
              style: TextStyle(
                fontWeight: isTotalRow ? FontWeight.bold : FontWeight.w500,
                fontSize: isTotalRow ? 15 : 13,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProportionalBar(
            person1Fraction: person1Fraction, tickFraction: tickFraction),
        const SizedBox(height: 8),
        Row(
          children: [
            DotLabel(
              PersonColors.person1,
              currencyFormat.format(person1Paid),
              dotSize: 6,
              gap: 5,
              textStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const Spacer(),
            DotLabel(
              PersonColors.person2,
              currencyFormat.format(person2Paid),
              dotSize: 6,
              gap: 5,
              textStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        verdict,
      ],
    );
  }
}
