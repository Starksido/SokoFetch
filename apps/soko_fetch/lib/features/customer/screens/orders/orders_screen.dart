import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: orders.when(
        loading: () => const LoadingList(),
        error: (e, _) => ErrorState(onRetry: () => ref.invalidate(ordersProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'When you order from a shop, it will show up here.',
            );
          }
          final active = list.where((o) => o.isActive).toList();
          final past = list.where((o) => !o.isActive).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ordersProvider),
            child: MaxWidth(
              child: ListView(
                padding: const EdgeInsets.only(bottom: SfSpace.xl),
                children: [
                  if (active.isNotEmpty) ...[
                    const SectionHeader('In progress'),
                    for (final o in active) _OrderRow(order: o),
                  ],
                  if (past.isNotEmpty) ...[
                    const SectionHeader('Past orders'),
                    for (final o in past) _OrderRow(order: o),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrderRow extends ConsumerStatefulWidget {
  const _OrderRow({required this.order});
  final OrderSummary order;

  @override
  ConsumerState<_OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends ConsumerState<_OrderRow> {
  bool _reordering = false;

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
        'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]}';
  }

  /// Refill the cart with this order's items that are still on the menu.
  Future<void> _reorder() async {
    final order = widget.order;
    setState(() => _reordering = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final detail = await ref.read(orderDetailProvider(order.id).future);
      ref.invalidate(merchantDetailProvider(order.merchantId));
      final shop = await ref.read(merchantDetailProvider(order.merchantId).future);
      final menu = {for (final m in shop.menuItems) m.id: m};
      final items = <CartItem>[];
      for (final raw in detail.items) {
        if (raw is! Map) continue;
        final item = menu[raw['item_id']];
        final qty = (raw['qty'] as num?)?.toInt() ?? 1;
        if (item != null && item.isAvailable) {
          items.add(CartItem(item: item, quantity: qty));
        }
      }
      if (items.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text("None of these items are available right now.")));
        return;
      }
      ref.read(cartProvider.notifier).replaceWith(order.merchantId, items);
      final missing = detail.items.length - items.length;
      if (missing > 0) {
        messenger.showSnackBar(SnackBar(
            content: Text('$missing item${missing == 1 ? ' is' : 's are'} '
                'no longer available and were left out.')));
      }
      navigator.pushNamed('/customer/cart');
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't reorder. Please try again.")));
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = widget.order;
    final name = o.merchantName ?? 'Order ${o.id.substring(0, 8)}';
    void open() =>
        Navigator.pushNamed(context, '/customer/tracking', arguments: o.id);

    return InkWell(
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SfSpace.md, vertical: SfSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: SfRadius.smAll,
              child: ImageFallback(
                  icon: Icons.storefront_outlined, label: name, width: 56, height: 56),
            ),
          ),
          const SizedBox(width: SfSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: SfSpace.xs),
                StatusPill.order(o.status),
              ]),
              const SizedBox(height: 2),
              Text(
                  '${o.itemCount} item${o.itemCount == 1 ? '' : 's'} · '
                  '${formatKes(o.total)} · ${_date(o.createdAt)}',
                  style: text.bodyMedium),
              if (o.isActive || o.canRate || o.isDelivered) ...[
                const SizedBox(height: SfSpace.xs),
                Wrap(spacing: SfSpace.xs, children: [
                  if (o.isActive) _PillAction('Track order', open),
                  if (o.canRate)
                    _PillAction(
                        'Rate',
                        () => Navigator.pushNamed(context, '/customer/rate-order',
                            arguments: o.id)),
                  if (o.isDelivered)
                    _PillAction(_reordering ? 'Loading…' : 'Reorder',
                        _reordering ? null : _reorder),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );
}
