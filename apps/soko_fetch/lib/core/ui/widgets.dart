import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'price.dart';

/// Section title with an optional action on the right ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title,
      {super.key, this.actionLabel, this.onAction,
      this.padding = const EdgeInsets.fromLTRB(
          SfSpace.md, SfSpace.lg, SfSpace.md, SfSpace.sm)});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ]),
      );
}

/// Star and rating in a grey pill; "New" when there are no ratings yet.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.rating, this.count});

  final double rating;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final isNew = rating <= 0 && (count ?? 0) == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: const BoxDecoration(
          color: SfColors.surface2, borderRadius: SfRadius.pillAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!isNew) ...[
          const Icon(Icons.star_rounded, size: 14, color: SfColors.rating),
          const SizedBox(width: 2),
        ],
        Text(
          isNew
              ? 'New'
              : '${rating.toStringAsFixed(1)}${count != null && count! > 0 ? ' ($count)' : ''}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ]),
    );
  }
}

/// A round "+" that turns into a − n + stepper once something is added.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.quantity, required this.onChanged,
      this.onSurface = false});

  final int quantity;
  final ValueChanged<int> onChanged;

  /// Over a photo: white background so it stands out.
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final bg = onSurface ? SfColors.surface : SfColors.surface2;
    if (quantity <= 0) {
      return Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onChanged(1),
          child: const SizedBox(
              width: 36, height: 36, child: Icon(Icons.add_rounded, size: 22)),
        ),
      );
    }
    Widget tap(IconData icon, int value, String label) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onChanged(value),
            child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 20)),
          ),
        );
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        tap(quantity == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            quantity - 1, 'Remove one'),
        Text('$quantity', style: Theme.of(context).textTheme.labelMedium),
        tap(Icons.add_rounded, quantity + 1, 'Add one'),
      ]),
    );
  }
}

/// Sticky full-width call to action at the bottom of a screen, e.g.
/// "3 · View cart · KES 1,250".
class BottomCtaBar extends StatelessWidget {
  const BottomCtaBar({super.key, required this.label, required this.onPressed,
      this.count, this.amount, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final int? count;
  final num? amount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final white = text.labelLarge!.copyWith(color: Colors.white);
    return DecoratedBox(
      decoration: const BoxDecoration(
          color: SfColors.surface, boxShadow: SfShadow.bar),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
            SfSpace.md, SfSpace.sm, SfSpace.md, SfSpace.sm),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: loading ? null : onPressed,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: SfSpace.md)),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Row(children: [
                    if (count != null)
                      Container(
                        constraints: const BoxConstraints(minWidth: 28),
                        height: 28,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: const BoxDecoration(
                            color: Color(0x33FFFFFF),
                            borderRadius: SfRadius.pillAll),
                        child: Text('$count', style: white),
                      ),
                    Expanded(
                      child: Text(label,
                          style: white,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (amount != null) Text(formatKes(amount!), style: white),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// A plain row: leading widget, title/subtitle, trailing widget.
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.title, this.subtitle, this.leading,
      this.trailing, this.onTap, this.titleStyle});

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SfSpace.md, vertical: SfSpace.sm),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: SfSpace.sm)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: titleStyle ?? text.titleSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: text.bodyMedium),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: SfSpace.xs), trailing!],
        ]),
      ),
    );
  }
}

/// A figure with a label on a grey tile (earnings, counts).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value,
      this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(SfSpace.md),
      decoration: const BoxDecoration(
          color: SfColors.surface2, borderRadius: SfRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: SfColors.inkMuted),
          const SizedBox(height: SfSpace.xs),
        ],
        Text(value, style: text.titleLarge, maxLines: 1),
        const SizedBox(height: 2),
        Text(label, style: text.bodySmall),
      ]),
    );
  }
}

/// An 8px grey band between sections (checkout, profile).
class SectionGap extends StatelessWidget {
  const SectionGap({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: SfSpace.xs, child: ColoredBox(color: SfColors.surface2));
}

/// Centres content and caps its width on tablets and desktop.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
