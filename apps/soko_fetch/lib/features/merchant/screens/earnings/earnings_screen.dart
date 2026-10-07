import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final todayAsync = ref.watch(todayEarningsProvider);
    final weeklyAsync = ref.watch(weeklyEarningsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todayEarningsProvider);
          ref.invalidate(weeklyEarningsProvider);
        },
        child: MaxWidth(
          maxWidth: 840,
          child: ListView(
            padding: const EdgeInsets.only(bottom: SfSpace.xl),
            children: [
              todayAsync.when(
                loading: () => const Padding(
                    padding: EdgeInsets.all(SfSpace.md),
                    child: Skeleton(height: 160, radius: SfRadius.md)),
                error: (_, __) =>
                    ErrorState(onRetry: () => ref.invalidate(todayEarningsProvider)),
                data: (d) => _Today(data: d),
              ),
              const SectionHeader('Last 7 days'),
              weeklyAsync.when(
                loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: SfSpace.md),
                    child: Skeleton(height: 200, radius: SfRadius.md)),
                error: (_, __) =>
                    ErrorState(onRetry: () => ref.invalidate(weeklyEarningsProvider)),
                data: (days) => days.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(SfSpace.md),
                        child: Text('No sales yet this week.', style: text.bodyMedium))
                    : Column(children: [
                        _WeeklyChart(days: days),
                        const SizedBox(height: SfSpace.md),
                        for (final d in days.reversed)
                          ListRow(
                            title: d.date,
                            subtitle:
                                '${d.totalOrders} order${d.totalOrders == 1 ? '' : 's'} · '
                                'sales ${formatKes(d.grossRevenue)} · fees ${formatKes(d.commissionDeducted)}',
                            trailing: Text(formatKes(d.netPayout),
                                style: text.titleSmall),
                          ),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final orders = data['total_orders'] as int? ?? 0;
    final gross = parseNum(data['gross_revenue']);
    final fees = parseNum(data['commission_deducted']);
    final net = parseNum(data['net_payout']);
    return Padding(
      padding: const EdgeInsets.all(SfSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your payout today', style: text.bodyMedium),
        Text(formatKes(net), style: text.displaySmall),
        Text('$orders order${orders == 1 ? '' : 's'}', style: text.bodyMedium),
        const SizedBox(height: SfSpace.md),
        Row(children: [
          Expanded(
            child: StatTile(
                label: 'Sales', value: formatKes(gross), icon: Icons.trending_up_rounded),
          ),
          const SizedBox(width: SfSpace.sm),
          Expanded(
            child: StatTile(
                label: 'Soko Fetch fee',
                value: formatKes(fees),
                icon: Icons.percent_rounded),
          ),
        ]),
      ]),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.days});
  final List<DailyEarnings> days;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final maxY = days.map((d) => d.netPayout).fold(0.0, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(SfSpace.xs, 0, SfSpace.md, 0),
      child: SizedBox(
        height: 200,
        child: BarChart(BarChartData(
          maxY: maxY > 0 ? maxY * 1.2 : 1000,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => SfColors.ink,
              getTooltipItem: (g, _, rod, __) => BarTooltipItem(
                  formatKes(rod.toY), text.labelSmall!.copyWith(color: Colors.white)),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  final parts = days[i].date.split('-');
                  return Text(parts.length >= 3 ? '${parts[2]}/${parts[1]}' : '',
                      style: text.bodySmall);
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (final e in days.asMap().entries)
              BarChartGroupData(x: e.key, barRods: [
                BarChartRodData(
                  toY: e.value.netPayout,
                  color: e.key == days.length - 1 ? SfColors.brand : SfColors.accentSoft,
                  width: 22,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        )),
      ),
    );
  }
}
