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
    final today = ref.watch(earningsProvider);
    final history = ref.watch(earningsHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(earningsProvider);
          ref.invalidate(earningsHistoryProvider);
        },
        child: MaxWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: SfSpace.xl),
            children: [
              today.when(
                loading: () => const Padding(
                    padding: EdgeInsets.all(SfSpace.md),
                    child: Skeleton(height: 160, radius: SfRadius.md)),
                error: (_, __) => ErrorState(
                    onRetry: () => ref.invalidate(earningsProvider)),
                data: (d) => _Today(data: d),
              ),
              const SectionHeader('Last 14 days'),
              history.when(
                loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: SfSpace.md),
                    child: Skeleton(height: 180, radius: SfRadius.md)),
                error: (_, __) => ErrorState(
                    onRetry: () => ref.invalidate(earningsHistoryProvider)),
                data: (days) => days.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(SfSpace.md),
                        child: Text('No deliveries yet.', style: text.bodyMedium),
                      )
                    : Column(children: [
                        _Chart(days: days),
                        const SizedBox(height: SfSpace.md),
                        for (final d in days.reversed)
                          ListRow(
                            leading: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: d.deliveries > 0
                                    ? SfColors.accentSoft
                                    : SfColors.surface2,
                                shape: BoxShape.circle,
                              ),
                              child: Text('${d.deliveries}',
                                  style: text.labelMedium!.copyWith(
                                      color: d.deliveries > 0
                                          ? SfColors.accentStrong
                                          : SfColors.inkFaint)),
                            ),
                            title: d.date,
                            subtitle:
                                '${d.deliveries} deliver${d.deliveries == 1 ? 'y' : 'ies'}',
                            trailing:
                                Text(formatKes(d.earned), style: text.titleSmall),
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
    final deliveries = data['deliveries'] as int? ?? 0;
    final earned = parseNum(data['earned']);
    final pending = parseNum(data['pending_payout']);
    final total = parseNum(data['total_earned']);
    return Padding(
      padding: const EdgeInsets.all(SfSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Today', style: text.bodyMedium),
        Text(formatKes(earned), style: text.displaySmall),
        Text('$deliveries deliver${deliveries == 1 ? 'y' : 'ies'}',
            style: text.bodyMedium),
        const SizedBox(height: SfSpace.md),
        Row(children: [
          Expanded(
            child: StatTile(
                label: 'Waiting to be paid',
                value: formatKes(pending),
                icon: Icons.account_balance_wallet_outlined),
          ),
          const SizedBox(width: SfSpace.sm),
          Expanded(
            child: StatTile(
                label: 'Earned in total',
                value: formatKes(total),
                icon: Icons.trending_up_rounded),
          ),
        ]),
      ]),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.days});
  final List<EarningsDay> days;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final maxY = days.map((d) => d.earned).fold(0.0, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(SfSpace.xs, 0, SfSpace.md, 0),
      child: SizedBox(
        height: 180,
        child: BarChart(BarChartData(
          maxY: maxY > 0 ? maxY * 1.2 : 1000,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => SfColors.ink,
              getTooltipItem: (g, _, rod, __) => BarTooltipItem(
                  formatKes(rod.toY),
                  text.labelSmall!.copyWith(color: Colors.white)),
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
                  return Text(parts.length >= 3 ? parts[2] : '',
                      style: text.bodySmall);
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (final e in days.asMap().entries)
              BarChartGroupData(x: e.key, barRods: [
                BarChartRodData(
                  toY: e.value.earned,
                  // Today in brand orange, earlier days softer
                  color: e.key == days.length - 1
                      ? SfColors.brand
                      : e.value.deliveries > 0
                          ? SfColors.accentSoft
                          : SfColors.surface3,
                  width: 14,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        )),
      ),
    );
  }
}
