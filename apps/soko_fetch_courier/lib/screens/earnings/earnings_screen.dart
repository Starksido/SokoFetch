import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today   = ref.watch(earningsProvider);
    final history = ref.watch(earningsHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async {
          ref.invalidate(earningsProvider);
          ref.invalidate(earningsHistoryProvider);
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // Today cards
          today.when(
            loading: () => const _LoadCard(),
            error:   (_, __) => const _ErrCard('today'),
            data:    (d) => _TodayCards(data: d),
          ),
          const SizedBox(height: 20),

          // 14-day chart
          const _Title('Last 14 Days — Earnings (KES)'),
          const SizedBox(height: 10),
          history.when(
            loading: () => const _LoadCard(h: 200),
            error:   (_, __) => const _ErrCard('history'),
            data:    (days) => _HistoryChart(days: days),
          ),
          const SizedBox(height: 20),

          // History list
          const _Title('Daily History'),
          const SizedBox(height: 8),
          history.when(
            loading: () => const _LoadCard(),
            error:   (_, __) => const _ErrCard('history'),
            data:    (days) => _HistoryList(days: days),
          ),
        ]),
      ),
    );
  }
}

class _TodayCards extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TodayCards({required this.data});

  @override
  Widget build(BuildContext context) {
    final deliveries  = data['deliveries'] as int? ?? 0;
    final earned      = parseNum(data['earned']);
    final pending     = parseNum(data['pending_payout']);
    final total       = parseNum(data['total_earned']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Title('Today'),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _Card(label: 'Deliveries', value: '$deliveries',
            icon: Icons.local_shipping_outlined, color: AppTheme.accent)),
        const SizedBox(width: 10),
        Expanded(child: _Card(label: 'Earned today', value: 'KES ${earned.toStringAsFixed(0)}',
            icon: Icons.payments_outlined, color: AppTheme.teal)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _Card(label: 'Pending payout', value: 'KES ${pending.toStringAsFixed(0)}',
            icon: Icons.account_balance_wallet_outlined, color: AppTheme.gold)),
        const SizedBox(width: 10),
        Expanded(child: _Card(label: 'Total earned', value: 'KES ${total.toStringAsFixed(0)}',
            icon: Icons.trending_up_outlined, color: AppTheme.brand)),
      ]),
    ]);
  }
}

class _Card extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Card({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: AppTheme.mgray, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ]),
    ),
  );
}

class _HistoryChart extends StatelessWidget {
  final List<EarningsDay> days;
  const _HistoryChart({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Card(child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No earnings yet',
              style: TextStyle(color: AppTheme.mgray)))));
    }
    final maxY = days.map((d) => d.earned).fold(0.0, (a, b) => a > b ? a : b);

    return Card(child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
      child: SizedBox(height: 180, child: BarChart(BarChartData(
        maxY: maxY * 1.25 > 0 ? maxY * 1.25 : 1000,
        barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (g, _, rod, __) => BarTooltipItem(
              'KES ${rod.toY.toStringAsFixed(0)}',
              const TextStyle(color: Colors.white, fontSize: 10)),
        )),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 24,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= days.length) return const Text('');
              final parts = days[i].date.split('-');
              return Text(parts.length >= 3 ? '${parts[2]}' : '',
                  style: const TextStyle(fontSize: 9, color: AppTheme.mgray));
            },
          )),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: days.asMap().entries.map((e) => BarChartGroupData(
          x: e.key,
          barRods: [BarChartRodData(
            toY: e.value.earned,
            color: e.value.deliveries > 0 ? AppTheme.accent : AppTheme.lgray,
            width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          )],
        )).toList(),
      ))),
    ));
  }
}

class _HistoryList extends StatelessWidget {
  final List<EarningsDay> days;
  const _HistoryList({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(20),
          child: Center(child: Text('No data', style: TextStyle(color: AppTheme.mgray)))));
    }
    return Card(child: Column(children: days.map((d) => ListTile(
      leading: CircleAvatar(
        backgroundColor: d.deliveries > 0
            ? AppTheme.accent.withOpacity(0.1) : AppTheme.lgray,
        child: Text('${d.deliveries}',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13,
                color: d.deliveries > 0 ? AppTheme.accent : AppTheme.mgray)),
      ),
      title: Text(d.date, style: const TextStyle(fontSize: 13)),
      subtitle: Text('${d.deliveries} deliveries',
          style: const TextStyle(fontSize: 12, color: AppTheme.mgray)),
      trailing: Text('KES ${d.earned.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.teal)),
    )).toList()));
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.brand));
}

class _LoadCard extends StatelessWidget {
  final double h;
  const _LoadCard({this.h = 80});
  @override
  Widget build(BuildContext context) => Card(
      child: SizedBox(height: h, child: const Center(
          child: CircularProgressIndicator(color: AppTheme.accent))));
}

class _ErrCard extends StatelessWidget {
  final String label;
  const _ErrCard(this.label);
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(padding: const EdgeInsets.all(16),
          child: Center(child: Text('Failed to load $label',
              style: const TextStyle(color: AppTheme.mgray)))));
}
