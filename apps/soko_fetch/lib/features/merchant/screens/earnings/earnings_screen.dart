import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync  = ref.watch(todayEarningsProvider);
    final weeklyAsync = ref.watch(weeklyEarningsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async {
          ref.invalidate(todayEarningsProvider);
          ref.invalidate(weeklyEarningsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Today summary cards ──────────────────────────────────────────
            todayAsync.when(
              loading: () => const _LoadingCard(),
              error:   (_, __) => const _ErrorCard('today summary'),
              data:    (d) => _TodaySummaryRow(data: d),
            ),
            const SizedBox(height: 20),

            // ── Weekly bar chart ─────────────────────────────────────────────
            const _SectionTitle('Last 7 Days — Net Payout (KES)'),
            const SizedBox(height: 12),
            weeklyAsync.when(
              loading: () => const _LoadingCard(height: 220),
              error:   (_, __) => const _ErrorCard('weekly chart'),
              data:    (days) => _WeeklyChart(days: days),
            ),
            const SizedBox(height: 20),

            // ── Weekly table ─────────────────────────────────────────────────
            const _SectionTitle('Daily Breakdown'),
            const SizedBox(height: 8),
            weeklyAsync.when(
              loading: () => const _LoadingCard(),
              error:   (_, __) => const _ErrorCard('breakdown'),
              data:    (days) => _DailyTable(days: days),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Today summary ─────────────────────────────────────────────────────────────
class _TodaySummaryRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TodaySummaryRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final orders = data['total_orders'] as int? ?? 0;
    final gross  = parseNum(data['gross_revenue']);
    final comm   = parseNum(data['commission_deducted']);
    final net    = parseNum(data['net_payout']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Today'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _SummaryCard(
              label: 'Orders', value: '$orders',
              icon: Icons.receipt_long_outlined, color: AppTheme.accent)),
          const SizedBox(width: 10),
          Expanded(child: _SummaryCard(
              label: 'Gross', value: 'KES ${gross.toStringAsFixed(0)}',
              icon: Icons.trending_up_outlined, color: AppTheme.gold)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _SummaryCard(
              label: 'Commission', value: 'KES ${comm.toStringAsFixed(0)}',
              icon: Icons.percent_outlined, color: AppTheme.mgray)),
          const SizedBox(width: 10),
          Expanded(child: _SummaryCard(
              label: 'Net Payout', value: 'KES ${net.toStringAsFixed(0)}',
              icon: Icons.account_balance_wallet_outlined,
              color: AppTheme.green)),
        ]),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.mgray, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      );
}

// ── Weekly bar chart ──────────────────────────────────────────────────────────
class _WeeklyChart extends StatelessWidget {
  final List<DailyEarnings> days;
  const _WeeklyChart({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('No earnings data yet',
              style: TextStyle(color: AppTheme.mgray))),
        ),
      );
    }

    final maxY = days.map((d) => d.netPayout).fold(0.0,
        (a, b) => a > b ? a : b);
    final chartMax = maxY * 1.25;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: chartMax > 0 ? chartMax : 1000,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    'KES ${rod.toY.toStringAsFixed(0)}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= days.length) return const Text('');
                      final date = days[i].date;
                      final parts = date.split('-');
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          parts.length >= 3 ? '${parts[2]}/${parts[1]}' : date,
                          style: const TextStyle(
                              fontSize: 10, color: AppTheme.mgray),
                        ),
                      );
                    },
                    reservedSize: 28,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    getTitlesWidget: (v, _) => Text(
                      v == 0 ? '0' : '${(v / 1000).toStringAsFixed(0)}K',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.mgray),
                    ),
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: days.asMap().entries.map((e) {
                final idx = e.key;
                final d   = e.value;
                return BarChartGroupData(
                  x: idx,
                  barRods: [
                    BarChartRodData(
                      toY: d.netPayout,
                      color: AppTheme.accent,
                      width: 18,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Daily table ───────────────────────────────────────────────────────────────
class _DailyTable extends StatelessWidget {
  final List<DailyEarnings> days;
  const _DailyTable({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text('No data',
                      style: TextStyle(color: AppTheme.mgray)))));
    }

    return Card(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: const [
                Expanded(
                    flex: 2,
                    child: Text('Date',
                        style: TextStyle(
                            color: AppTheme.mgray,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
                Expanded(
                    child: Text('Orders',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppTheme.mgray,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
                Expanded(
                    child: Text('Gross',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: AppTheme.mgray,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
                Expanded(
                    child: Text('Net',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: AppTheme.mgray,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
              ],
            ),
          ),
          const Divider(height: 1),
          ...days.map((d) => _TableRow(day: d)),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final DailyEarnings day;
  const _TableRow({required this.day});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: Text(day.date,
                  style: const TextStyle(fontSize: 13))),
          Expanded(
              child: Text('${day.totalOrders}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13))),
          Expanded(
              child: Text('${day.grossRevenue.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13))),
          Expanded(
              child: Text('${day.netPayout.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent))),
        ]),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.brand));
}

class _LoadingCard extends StatelessWidget {
  final double height;
  const _LoadingCard({this.height = 100});
  @override
  Widget build(BuildContext context) => Card(
      child: SizedBox(
          height: height,
          child: const Center(
              child: CircularProgressIndicator(color: AppTheme.accent))));
}

class _ErrorCard extends StatelessWidget {
  final String label;
  const _ErrorCard(this.label);
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
              child: Text('Failed to load $label',
                  style: const TextStyle(color: AppTheme.mgray)))));
}

