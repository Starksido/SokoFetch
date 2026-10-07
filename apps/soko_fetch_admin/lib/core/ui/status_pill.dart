import 'package:flutter/material.dart';

import '../design/tokens.dart';

enum PillTone { neutral, dark, accent, success, warning, danger }

/// Small rounded label for statuses and tags.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label,
      {super.key, this.tone = PillTone.neutral, this.icon});

  /// The pill for an order status, e.g. `StatusPill.order('in_transit')`.
  factory StatusPill.order(String status, {Key? key}) {
    final (label, tone) = orderStatusStyle(status);
    return StatusPill(label, key: key, tone: tone);
  }

  final String label;
  final PillTone tone;
  final IconData? icon;

  static (Color bg, Color fg) colorsFor(PillTone tone) => switch (tone) {
        PillTone.neutral => (SfColors.surface2, SfColors.ink),
        PillTone.dark => (SfColors.ink, Colors.white),
        PillTone.accent => (SfColors.accentSoft, SfColors.accentStrong),
        PillTone.success => (SfColors.successSoft, SfColors.success),
        PillTone.warning => (SfColors.warningSoft, SfColors.warning),
        PillTone.danger => (SfColors.dangerSoft, SfColors.danger),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colorsFor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: SfRadius.pillAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: SfSpace.xxs),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall!
                  .copyWith(color: fg)),
        ),
      ]),
    );
  }
}

/// Customer-friendly label and tone for an order status.
(String, PillTone) orderStatusStyle(String status) => switch (status) {
      'pending' => ('Waiting for shop', PillTone.warning),
      'confirmed' => ('Confirmed', PillTone.neutral),
      'preparing' => ('Preparing', PillTone.accent),
      'ready_for_pickup' => ('Ready for pickup', PillTone.accent),
      'picked_up' => ('Picked up', PillTone.accent),
      'in_transit' => ('On the way', PillTone.accent),
      'delivered' => ('Delivered', PillTone.success),
      'cancelled' => ('Cancelled', PillTone.danger),
      'delivery_failed' => ('Delivery failed', PillTone.danger),
      _ => (status.replaceAll('_', ' '), PillTone.neutral),
    };
