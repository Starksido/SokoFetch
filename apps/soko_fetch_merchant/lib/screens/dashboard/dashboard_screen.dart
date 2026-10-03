import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../config/app_theme.dart';
import '../../models/models.dart';
import '../../network/api_client.dart';
import '../../providers/providers.dart';
import '../orders/order_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _pollTimer;
  final _audio = AudioPlayer();
  Set<String> _knownOrderIds = {};
  bool _isOpen = true;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _startPolling();
    _loadShopStatus();
  }

  Future<void> _loadShopStatus() async {
    try {
      final resp = await ApiClient.instance.get('/merchant/me');
      if (mounted) {
        setState(() => _isOpen = resp.data['is_open'] as bool? ?? true);
      }
    } catch (_) {}
  }

  void _startPolling() {
    ref.listenManual<AsyncValue<List<Order>>>(liveOrdersProvider, (_, next) {
      next.whenData((orders) {
        final pendingIds =
            orders.where((o) => o.isPending).map((o) => o.id).toSet();
        final newIds = pendingIds.difference(_knownOrderIds);
        if (newIds.isNotEmpty) {
          _playAlert();
        }
        _knownOrderIds = pendingIds;
      });
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(liveOrdersProvider);
    });
  }

  Future<void> _playAlert() async {
    try {
      await _audio.play(AssetSource('sounds/order_alert.mp3'));
    } catch (_) {}
  }

  Future<void> _toggleShopOpen(bool val) async {
    setState(() => _isOpen = val);
    try {
      await ApiClient.instance.put('/merchant/me/open?is_open=$val');
    } catch (_) {
      setState(() => _isOpen = !val);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _audio.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveOrders = ref.watch(liveOrdersProvider);
    final profileAsync = ref.watch(merchantProfileProvider);
    final earningsAsync = ref.watch(todayEarningsProvider);

    return Scaffold(
      backgroundColor: AppTheme.lgray,
      appBar: AppBar(
        title: const Text('Soko Fetch'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {},
            icon:
                const Icon(Icons.notifications_outlined, color: AppTheme.mgray),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryContainer,
              child: Text(
                profileAsync.maybeWhen(
                  data: (p) => _initials(p.shopName),
                  orElse: () => 'SF',
                ),
                style: const TextStyle(
                  color: Color(0xFF5F1900),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: liveOrders.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (_, __) =>
            _ErrorPanel(onRetry: () => ref.invalidate(liveOrdersProvider)),
        data: (orders) {
          final pending = orders.where((o) => o.isPending).toList();
          final active =
              orders.where((o) => !o.isPending && !o.isTerminal).toList();
          final toPrep =
              orders.where((o) => o.isConfirmed || o.isPreparing).toList();
          final totalRevenue = earningsAsync.maybeWhen(
            data: (data) => parseNum(
              data['gross_revenue'] ??
                  data['total_revenue'] ??
                  data['today_revenue'] ??
                  data['net_payout'],
            ),
            orElse: () => orders.fold<double>(0, (sum, o) => sum + o.subtotal),
          );

          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () async {
              ref.invalidate(liveOrdersProvider);
              ref.invalidate(todayEarningsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              children: [
                _StatusHeader(
                  isOpen: _isOpen,
                  onChanged: _toggleShopOpen,
                  shopName: profileAsync.maybeWhen(
                    data: (p) => p.shopName,
                    orElse: () => 'Your shop',
                  ),
                ),
                const SizedBox(height: 16),
                _StatsGrid(
                  revenue: totalRevenue,
                  orders: orders.length,
                  avgPrep: profileAsync.maybeWhen(
                    data: (p) => p.avgPrepMinutes,
                    orElse: () => 12,
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                    title: 'New Orders',
                    count: pending.length,
                    action: 'View All'),
                const SizedBox(height: 12),
                if (pending.isEmpty)
                  _QuietPanel(
                    icon: Icons.receipt_long_outlined,
                    title: 'No new orders',
                    body: _isOpen
                        ? 'Fresh orders will appear here automatically.'
                        : 'Your shop is closed. Open it to receive orders.',
                  )
                else
                  ...pending.map((order) => OrderCard(
                        order: order,
                        onStatusChanged: () =>
                            ref.invalidate(liveOrdersProvider),
                      )),
                const SizedBox(height: 24),
                _SectionHeader(title: 'To Prep', count: toPrep.length),
                const SizedBox(height: 12),
                if (toPrep.isEmpty)
                  const _QuietPanel(
                    icon: Icons.restaurant_menu_rounded,
                    title: 'Prep queue is clear',
                    body: 'Accepted orders will move into this section.',
                  )
                else
                  ...toPrep.map((order) => OrderCard(
                        order: order,
                        onStatusChanged: () =>
                            ref.invalidate(liveOrdersProvider),
                      )),
                if (active.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(title: 'In Progress', count: active.length),
                  const SizedBox(height: 12),
                  ...active.map((order) => OrderCard(
                        order: order,
                        onStatusChanged: () =>
                            ref.invalidate(liveOrdersProvider),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _initials(String value) {
    final parts =
        value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'SF';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _StatusHeader extends StatelessWidget {
  final bool isOpen;
  final ValueChanged<bool> onChanged;
  final String shopName;

  const _StatusHeader({
    required this.isOpen,
    required this.onChanged,
    required this.shopName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color:
                  isOpen ? AppTheme.secondaryContainer : AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isOpen ? Icons.storefront_rounded : Icons.storefront_outlined,
              color: isOpen ? AppTheme.secondary : AppTheme.mgray,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shopName,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  isOpen ? 'Open and accepting orders' : 'Closed to new orders',
                  style: const TextStyle(color: AppTheme.mgray, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: isOpen,
            onChanged: onChanged,
            activeColor: AppTheme.secondary,
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final double revenue;
  final int orders;
  final int avgPrep;

  const _StatsGrid({
    required this.revenue,
    required this.orders,
    required this.avgPrep,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                bottom: -20,
                child: Icon(Icons.payments_rounded,
                    size: 112, color: Colors.black.withOpacity(0.08)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's Total Revenue",
                    style: TextStyle(
                      color: Color(0xFF5F1900),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'KES ${revenue.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFF5F1900),
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                icon: Icons.shopping_bag_rounded,
                label: 'Orders',
                value: '$orders',
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                icon: Icons.timer_rounded,
                label: 'Avg. Prep',
                value: '${avgPrep}m',
                color: AppTheme.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(color: AppTheme.mgray, fontSize: 12)),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final String? action;

  const _SectionHeader({required this.title, required this.count, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            '$title ($count)',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          Text(
            action!,
            style: const TextStyle(
                color: AppTheme.accent, fontWeight: FontWeight.w700),
          ),
      ],
    );
  }
}

class _QuietPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _QuietPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppTheme.mgray),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mgray)),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorPanel({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: AppTheme.mgray),
            const SizedBox(height: 12),
            const Text('Could not load orders',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
