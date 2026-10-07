import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../../../core/api_client.dart';
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
  _Tab _tab = _Tab.newOrders;
  String? _selectedId; // Tablet split view

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

  List<Order> _ordersFor(_Tab tab, List<Order> orders) => switch (tab) {
        _Tab.newOrders => orders.where((o) => o.isPending).toList(),
        _Tab.preparing =>
          orders.where((o) => o.isConfirmed || o.isPreparing).toList(),
        _Tab.ready => orders
            .where((o) => !o.isPending && !o.isConfirmed && !o.isPreparing && !o.isTerminal)
            .toList(),
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final liveOrders = ref.watch(liveOrdersProvider);
    final profile = ref.watch(merchantProfileProvider).valueOrNull;
    final earnings = ref.watch(todayEarningsProvider).valueOrNull;
    final wide = Breakpoint.of(context) == Breakpoint.expanded;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: liveOrders.when(
          loading: () => const LoadingList(),
          error: (_, __) => ErrorState(
              message: "Couldn't load your orders.",
              onRetry: () => ref.invalidate(liveOrdersProvider)),
          data: (orders) {
            final list = _ordersFor(_tab, orders);
            final revenue = earnings == null
                ? orders.fold<double>(0, (sum, o) => sum + o.subtotal)
                : parseNum(earnings['gross_revenue'] ??
                    earnings['total_revenue'] ??
                    earnings['net_payout']);

            final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    SfSpace.md, SfSpace.md, SfSpace.md, 0),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(profile?.shopName ?? 'Your shop',
                          style: text.headlineSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(_isOpen ? 'Open · taking orders' : 'Paused · not taking orders',
                          style: text.bodyMedium!.copyWith(
                              color: _isOpen ? SfColors.success : SfColors.inkMuted)),
                    ]),
                  ),
                  Switch(value: _isOpen, onChanged: _toggleShopOpen),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(SfSpace.md),
                child: Row(children: [
                  Expanded(
                    child: StatTile(
                        label: 'Today',
                        value: formatKes(revenue),
                        icon: Icons.payments_outlined),
                  ),
                  const SizedBox(width: SfSpace.sm),
                  Expanded(
                    child: StatTile(
                        label: 'Orders',
                        value: '${orders.length}',
                        icon: Icons.receipt_long_outlined),
                  ),
                  const SizedBox(width: SfSpace.sm),
                  Expanded(
                    child: StatTile(
                        label: 'Avg. prep',
                        value: '${profile?.avgPrepMinutes ?? 20} min',
                        icon: Icons.timer_outlined),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SfSpace.md),
                child: Wrap(spacing: SfSpace.xs, runSpacing: SfSpace.xs, children: [
                  for (final t in _Tab.values)
                    ChoiceChip(
                      label: Text('${t.label} · ${_ordersFor(t, orders).length}'),
                      selected: _tab == t,
                      onSelected: (_) => setState(() {
                        _tab = t;
                        _selectedId = null;
                      }),
                    ),
                ]),
              ),
              const SizedBox(height: SfSpace.sm),
            ]);

            final empty = EmptyState(
              icon: _tab.icon,
              title: _tab.emptyTitle,
              message: _tab == _Tab.newOrders && !_isOpen
                  ? 'Your shop is paused. Switch it on to take orders.'
                  : _tab.emptyMessage,
            );

            Future<void> refresh() async {
              ref.invalidate(liveOrdersProvider);
              ref.invalidate(todayEarningsProvider);
            }

            if (!wide) {
              return RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: SfSpace.xl),
                  children: [
                    header,
                    if (list.isEmpty)
                      Padding(padding: const EdgeInsets.only(top: SfSpace.xl), child: empty)
                    else
                      for (final o in list)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              SfSpace.md, 0, SfSpace.md, SfSpace.sm),
                          child: OrderCard(
                            key: ValueKey(o.id),
                            order: o,
                            onStatusChanged: () => ref.invalidate(liveOrdersProvider),
                          ),
                        ),
                  ],
                ),
              );
            }

            // Tablet: list on the left, the selected order on the right
            final selected = list.where((o) => o.id == _selectedId).firstOrNull ??
                list.firstOrNull;
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 400,
                child: RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(children: [
                    header,
                    if (list.isEmpty)
                      Padding(padding: const EdgeInsets.only(top: SfSpace.xl), child: empty),
                    for (final o in list)
                      _OrderRow(
                        order: o,
                        selected: o.id == selected?.id,
                        onTap: () => setState(() => _selectedId = o.id),
                      ),
                  ]),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? const EmptyState(
                        icon: Icons.touch_app_outlined,
                        title: 'No order selected',
                        message: 'Orders you pick from the list show here.')
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(SfSpace.lg),
                        child: MaxWidth(
                          child: OrderCard(
                            key: ValueKey(selected.id),
                            order: selected,
                            onStatusChanged: () => ref.invalidate(liveOrdersProvider),
                          ),
                        ),
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

enum _Tab {
  newOrders('New', Icons.notifications_none_rounded, 'No new orders',
      'New orders appear here automatically.'),
  preparing('Preparing', Icons.restaurant_menu_rounded, 'Nothing to prepare',
      'Orders you accept move here.'),
  ready('Ready', Icons.delivery_dining_outlined, 'Nothing waiting for a rider',
      'Orders ready for pickup show here until a rider collects them.');

  const _Tab(this.label, this.icon, this.emptyTitle, this.emptyMessage);
  final String label;
  final IconData icon;
  final String emptyTitle;
  final String emptyMessage;
}

/// Compact order row for the tablet list.
class _OrderRow extends StatelessWidget {
  const _OrderRow(
      {required this.order, required this.selected, required this.onTap});

  final Order order;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = merchantStatusStyle(order.status);
    return Material(
      color: selected ? SfColors.surface2 : SfColors.surface,
      child: ListRow(
        title: '#${order.id.substring(0, 8).toUpperCase()}',
        subtitle:
            '${order.itemCount} item${order.itemCount == 1 ? '' : 's'} · ${timeago.format(order.createdAt)}',
        trailing: StatusPill(label, tone: tone),
        onTap: onTap,
      ),
    );
  }
}
