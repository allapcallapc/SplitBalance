import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/spend_chart_data.dart';
import 'ledger_visuals.dart';

// A horizontally-scrollable stacked bar chart of monthly spend, split by
// person. Scrolls because the detail screens chart the bill's entire
// history rather than a fixed lookback window, so the number of months can
// exceed what fits on screen. Caller must ensure [months] is non-empty.
class MonthlySpendBarChart extends StatelessWidget {
  const MonthlySpendBarChart({
    super.key,
    required this.months,
    required this.currencyFormat,
  });

  final List<MonthlySpend> months;
  final NumberFormat currencyFormat;

  static const double _barSlotWidth = 56;
  static const double _chartHeight = 220;

  @override
  Widget build(BuildContext context) {
    final maxTotal =
        months.fold<double>(0, (max, m) => m.total > max ? m.total : max);
    // Headroom above the tallest bar so it doesn't touch the chart's top.
    final maxY = maxTotal <= 0 ? 1.0 : maxTotal * 1.15;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            math.max(constraints.maxWidth, months.length * _barSlotWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: _chartHeight,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final month = months[group.x.toInt()];
                      return BarTooltipItem(
                        '${DateFormat('MMM yyyy').format(month.month)}\n'
                        '${currencyFormat.format(month.total)}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => Text(
                        currencyFormat.format(value),
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= months.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            DateFormat('MMM yy').format(months[index].month),
                            style:
                                TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withValues(alpha: 0.15),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < months.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: months[i].total,
                          width: 18,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(4)),
                          rodStackItems: [
                            BarChartRodStackItem(
                              0,
                              months[i].person1Amount,
                              PersonColors.person1,
                            ),
                            BarChartRodStackItem(
                              months[i].person1Amount,
                              months[i].total,
                              PersonColors.person2,
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// A running-total line chart plotting cumulative spend against real elapsed
// time (not bill index), so gaps between bills read as gaps on the chart.
// Caller must ensure [points] is non-empty.
class CumulativeSpendLineChart extends StatelessWidget {
  const CumulativeSpendLineChart({
    super.key,
    required this.points,
    required this.currencyFormat,
  });

  final List<CumulativeSpendPoint> points;
  final NumberFormat currencyFormat;

  static const double _chartHeight = 220;

  @override
  Widget build(BuildContext context) {
    final firstDate = points.first.date;
    final lastDate = points.last.date;
    final totalDays = math.max(1, lastDate.difference(firstDate).inDays);
    final maxAmount = points.last.cumulativeAmount;
    final maxY = maxAmount <= 0 ? 1.0 : maxAmount * 1.1;

    final spots = points
        .map((p) => FlSpot(
              p.date.difference(firstDate).inDays.toDouble(),
              p.cumulativeAmount,
            ))
        .toList();

    final lineColor = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: _chartHeight,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: totalDays.toDouble(),
          minY: 0,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final date = firstDate.add(Duration(days: spot.x.round()));
                return LineTooltipItem(
                  '${DateFormat('MMM d, yyyy').format(date)}\n'
                  '${currencyFormat.format(spot.y)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList(),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) => Text(
                  currencyFormat.format(value),
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: math.max(1, totalDays / 4),
                getTitlesWidget: (value, meta) {
                  final date = firstDate.add(Duration(days: value.round()));
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      DateFormat('MMM yy').format(date),
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: lineColor,
              barWidth: 2.5,
              dotData: FlDotData(show: points.length <= 30),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
