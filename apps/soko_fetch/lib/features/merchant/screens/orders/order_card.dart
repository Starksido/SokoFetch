import 'dart:async';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme.dart';
import '../../models/models.dart';
import '../../../../core/api_client.dart';

class OrderCard extends StatefulWidget {
  final Order order;
  final VoidCallback onStatusChanged;
  const OrderCard(
      {super.key, required this.order, required this.onStatusChanged});
  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  Timer? _countdown;
  int _secondsLeft = 90;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(covariant OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCountdown();
  }

  /// The accept countdown runs only while the order is pending AND paid —
  /// unpaid orders can't be accepted yet, so they must not be auto-declined
  /// while the customer is still paying. It starts when this card first sees
  /// the order as paid (there is no paid-at time from the server).
  void _syncCountdown() {
    final o = widget.order;
    final shouldRun = o.isPending && o.isPaid;
    if (shouldRun && _countdown == null) {
      _startCountdown();
    } else if (!shouldRun) {
      _countdown?.cancel();
      _countdown = null;
    }
  }

  void _startCountdown() {
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 0) {
        t.cancel();
        // Auto-decline: silently update to cancelled
        _updateStatus('cancelled', reason: 'Auto-declined: no response');
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _updateStatus(String status, {String? reason}) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await ApiClient.instance
          .put('/orders/${widget.order.id}/status', data: {
        'status': status,
        if (reason != null) 'cancellation_reason': reason,
      });
      widget.onStatusChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${o.id.substring(0, 8).toUpperCase()}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(timeago.format(o.createdAt),
                        style: const TextStyle(
                            color: AppTheme.mgray, fontSize: 12)),
                  ]),
            ),
            _StatusChip(status: o.status),
            if (o.isPending && o.isPaid) ...[
              const SizedBox(width: 8),
              _CountdownBadge(seconds: _secondsLeft),
            ],
          ]),

          const Divider(height: 20),

          // Items list
          ...o.items.map((item) {
            final name = item['name'] as String? ?? 'Item';
            final qty  = item['qty']  as int?    ?? 1;
            final sub  = parseNum(item['subtotal']);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$qty× $name',
                        style: const TextStyle(fontSize: 13)),
                    Text('KES ${sub.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ]),
            );
          }),

          const Divider(height: 16),

          // Totals
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Subtotal', style: TextStyle(color: AppTheme.mgray)),
            Text('KES ${o.subtotal.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Your payout', style: TextStyle(color: AppTheme.mgray)),
            Text('KES ${o.netPayout.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.accent)),
          ]),

          if (o.specialInstructions != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppTheme.gold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(o.specialInstructions!,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.brand)),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 16),

          // Action buttons
          if (!_acting) _buildActions(o) else
            const Center(
                child: CircularProgressIndicator(color: AppTheme.accent)),
        ]),
      ),
    );
  }

  Widget _buildActions(Order o) {
    if (o.awaitingPayment) {
      return Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _updateStatus('cancelled',
                reason: 'Merchant declined'),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.red),
                foregroundColor: AppTheme.red),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          flex: 2,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_top_rounded,
                    color: AppTheme.gold, size: 18),
                SizedBox(width: 6),
                Text('Awaiting payment',
                    style: TextStyle(
                        color: AppTheme.mgray, fontWeight: FontWeight.w600)),
              ]),
        ),
      ]);
    }

    if (o.isPending) {
      return Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _updateStatus('cancelled',
                reason: 'Merchant declined'),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.red),
                foregroundColor: AppTheme.red),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: () => _updateStatus('confirmed'),
            child: const Text('Accept Order'),
          ),
        ),
      ]);
    }

    if (o.isConfirmed) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _updateStatus('preparing'),
          icon: const Icon(Icons.restaurant_menu, size: 18),
          label: const Text('Start Preparing'),
        ),
      );
    }

    if (o.isPreparing) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _updateStatus('ready_for_pickup'),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Mark Ready for Pickup'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green),
        ),
      );
    }

    if (o.isReadyForPickup) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10)),
        child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_shipping_outlined,
                  color: AppTheme.accent, size: 18),
              SizedBox(width: 8),
              Text('Waiting for rider pickup',
                  style: TextStyle(color: AppTheme.accent,
                      fontWeight: FontWeight.w600)),
            ]),
      );
    }

    return const SizedBox.shrink();
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'pending':          return AppTheme.red;
      case 'confirmed':        return AppTheme.gold;
      case 'preparing':        return AppTheme.gold;
      case 'ready_for_pickup': return AppTheme.accent;
      default:                 return AppTheme.mgray;
    }
  }

  String get _label {
    switch (status) {
      case 'pending':          return 'NEW';
      case 'confirmed':        return 'CONFIRMED';
      case 'preparing':        return 'PREPARING';
      case 'ready_for_pickup': return 'READY';
      case 'picked_up':        return 'PICKED UP';
      case 'in_transit':       return 'IN TRANSIT';
      default: return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(_label,
            style: TextStyle(
                color: _color, fontSize: 10, fontWeight: FontWeight.bold)),
      );
}

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) => Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
            color: seconds <= 30
                ? AppTheme.red.withValues(alpha: 0.12)
                : AppTheme.lgray,
            shape: BoxShape.circle),
        child: Center(
          child: Text('$seconds',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: seconds <= 30 ? AppTheme.red : AppTheme.mgray)),
        ),
      );
}

