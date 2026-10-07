import 'dart:async';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/errors.dart';
import '../../../../core/ui/ui.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMessage(e, "Couldn't update the order."))));
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
    final text = Theme.of(context).textTheme;
    final o = widget.order;
    final (label, tone) = merchantStatusStyle(o.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SfSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${o.id.substring(0, 8).toUpperCase()}',
                    style: text.titleMedium),
                Text(
                    '${o.itemCount} item${o.itemCount == 1 ? '' : 's'} · '
                    '${timeago.format(o.createdAt)}',
                    style: text.bodySmall),
              ]),
            ),
            StatusPill(label, tone: tone),
            if (o.isPending && o.isPaid) ...[
              const SizedBox(width: SfSpace.xs),
              _CountdownBadge(seconds: _secondsLeft),
            ],
          ]),
          const SizedBox(height: SfSpace.sm),
          const Divider(),
          const SizedBox(height: SfSpace.sm),
          for (final item in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                  width: 32,
                  child: Text('${item['qty'] ?? 1}×', style: text.titleSmall),
                ),
                Expanded(
                    child: Text('${item['name'] ?? 'Item'}', style: text.bodyLarge)),
                Text(formatKes(parseNum(item['subtotal'])), style: text.bodyMedium),
              ]),
            ),
          if (o.specialInstructions != null) ...[
            const SizedBox(height: SfSpace.sm),
            InlineMessage(o.specialInstructions!, isError: false),
          ],
          const SizedBox(height: SfSpace.sm),
          Row(children: [
            Expanded(child: Text('Your payout', style: text.bodyMedium)),
            Text(formatKes(o.netPayout),
                style: text.titleSmall!.copyWith(color: SfColors.accentStrong)),
          ]),
          const SizedBox(height: SfSpace.md),
          if (_acting) const SfLoader() else _buildActions(o),
        ]),
      ),
    );
  }

  Widget _buildActions(Order o) {
    final text = Theme.of(context).textTheme;
    final decline = SfButton.destructive(
      label: 'Decline',
      onPressed: () => _updateStatus('cancelled', reason: 'Merchant declined'),
    );
    if (o.awaitingPayment) {
      return Row(children: [
        Expanded(child: decline),
        const SizedBox(width: SfSpace.sm),
        const Expanded(
          flex: 2,
          child: Center(
            child: StatusPill('Waiting for payment',
                tone: PillTone.warning, icon: Icons.hourglass_top_rounded),
          ),
        ),
      ]);
    }
    if (o.isPending) {
      return Row(children: [
        Expanded(child: decline),
        const SizedBox(width: SfSpace.sm),
        Expanded(
          flex: 2,
          child: SfButton.primary(
              label: 'Accept', onPressed: () => _updateStatus('confirmed')),
        ),
      ]);
    }
    if (o.isConfirmed) {
      return SfButton.primary(
        label: 'Start preparing',
        icon: Icons.restaurant_menu_rounded,
        onPressed: () => _updateStatus('preparing'),
      );
    }
    if (o.isPreparing) {
      return SfButton.primary(
        label: 'Mark ready for pickup',
        icon: Icons.check_circle_outline_rounded,
        onPressed: () => _updateStatus('ready_for_pickup'),
      );
    }
    if (o.isReadyForPickup) {
      return Row(children: [
        const Icon(Icons.delivery_dining_outlined, color: SfColors.accentStrong),
        const SizedBox(width: SfSpace.xs),
        Text('Waiting for the rider', style: text.titleSmall),
      ]);
    }
    return const SizedBox.shrink();
  }
}

/// Merchant wording for order statuses.
(String, PillTone) merchantStatusStyle(String status) => switch (status) {
      'pending' => ('New', PillTone.accent),
      'confirmed' => ('Accepted', PillTone.neutral),
      'preparing' => ('Preparing', PillTone.warning),
      'ready_for_pickup' => ('Ready', PillTone.success),
      'picked_up' => ('With rider', PillTone.neutral),
      'in_transit' => ('On the way', PillTone.neutral),
      _ => orderStatusStyle(status),
    };

class _CountdownBadge extends StatelessWidget {
  final int seconds;
  const _CountdownBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final urgent = seconds <= 30;
    return Semantics(
      label: '$seconds seconds to accept',
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: urgent ? SfColors.dangerSoft : SfColors.surface2,
            shape: BoxShape.circle),
        child: Center(
          child: Text('$seconds',
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: urgent ? SfColors.danger : SfColors.ink)),
        ),
      ),
    );
  }
}
