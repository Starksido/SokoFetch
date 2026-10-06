import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: ordersAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.mgray),
            const SizedBox(height: 12),
            const Text('Could not load orders'),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: () => ref.invalidate(ordersProvider),
                child: const Text('Retry')),
          ]),
        ),
        data: (orders) => orders.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 72, color: AppTheme.mgray),
                    SizedBox(height: 16),
                    Text('No orders yet',
                        style: TextStyle(color: AppTheme.mgray, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('Your order history will appear here.',
                        style: TextStyle(color: AppTheme.mgray, fontSize: 13)),
                  ],
                ),
              )
            : RefreshIndicator(
                color: AppTheme.accent,
                onRefresh: () async => ref.invalidate(ordersProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _OrderCard(order: orders[i]),
                ),
              ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderSummary order;
  const _OrderCard({required this.order});

  Color get _statusColor {
    switch (order.status) {
      case 'delivered':     return AppTheme.teal;
      case 'cancelled':
      case 'delivery_failed': return AppTheme.accent;
      default:              return AppTheme.gold;
    }
  }

  IconData get _statusIcon {
    switch (order.status) {
      case 'delivered':     return Icons.check_circle_outline;
      case 'cancelled':     return Icons.cancel_outlined;
      case 'in_transit':    return Icons.local_shipping_outlined;
      case 'preparing':     return Icons.restaurant_outlined;
      default:              return Icons.schedule_outlined;
    }
  }

  String get _statusLabel {
    switch (order.status) {
      case 'pending':           return 'Pending';
      case 'confirmed':         return 'Confirmed';
      case 'preparing':         return 'Preparing';
      case 'ready_for_pickup':  return 'Ready for pickup';
      case 'picked_up':         return 'Picked up';
      case 'in_transit':        return 'On the way';
      case 'delivered':         return 'Delivered';
      case 'cancelled':         return 'Cancelled';
      case 'delivery_failed':   return 'Delivery failed';
      default:                  return order.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          if (order.isActive) {
            Navigator.pushNamed(context, '/customer/tracking', arguments: order.id);
          } else if (order.canRate) {
            Navigator.pushNamed(context, '/customer/rate-order', arguments: order.id);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(children: [
                Expanded(
                  child: Text(
                    order.merchantName ?? 'Order #${order.id.substring(0, 8)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_statusIcon, size: 13, color: _statusColor),
                    const SizedBox(width: 4),
                    Text(_statusLabel,
                        style: TextStyle(
                            color: _statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              // Items summary
              Text(
                '${order.itemCount} item(s)  •  KES ${order.total.toStringAsFixed(0)}',
                style: const TextStyle(color: AppTheme.mgray, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                timeago.format(order.createdAt),
                style: const TextStyle(color: AppTheme.mgray, fontSize: 12),
              ),
              // Action buttons
              if (order.isActive || order.canRate) ...[
                const SizedBox(height: 12),
                Row(children: [
                  if (order.isActive)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pushNamed(
                            context, '/customer/tracking',
                            arguments: order.id),
                        icon: const Icon(Icons.gps_fixed, size: 16),
                        label: const Text('Track Order'),
                        style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10)),
                      ),
                    ),
                  if (order.canRate)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pushNamed(
                            context, '/customer/rate-order',
                            arguments: order.id),
                        icon: const Icon(Icons.star_border,
                            size: 16, color: AppTheme.accent),
                        label: const Text('Rate',
                            style: TextStyle(color: AppTheme.accent)),
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.accent),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10)),
                      ),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
