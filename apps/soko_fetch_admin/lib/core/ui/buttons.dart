import 'package:flutter/material.dart';

import '../design/tokens.dart';

enum _Kind { primary, secondary, outline, text, destructive }

/// Pill buttons. Primary is black, secondary grey, outline ink-bordered,
/// text plain, destructive red. Full width by default ([expand]); pass
/// `expand: false` inside rows.
class SfButton extends StatelessWidget {
  const SfButton.primary({super.key, required this.label, this.onPressed,
      this.icon, this.loading = false, this.expand = true})
      : _kind = _Kind.primary;
  const SfButton.secondary({super.key, required this.label, this.onPressed,
      this.icon, this.loading = false, this.expand = true})
      : _kind = _Kind.secondary;
  const SfButton.outline({super.key, required this.label, this.onPressed,
      this.icon, this.loading = false, this.expand = true})
      : _kind = _Kind.outline;
  const SfButton.text({super.key, required this.label, this.onPressed,
      this.icon, this.loading = false, this.expand = false})
      : _kind = _Kind.text;
  const SfButton.destructive({super.key, required this.label, this.onPressed,
      this.icon, this.loading = false, this.expand = true})
      : _kind = _Kind.destructive;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final _Kind _kind;

  @override
  Widget build(BuildContext context) {
    final onDark = _kind == _Kind.primary;
    final Widget child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: onDark ? Colors.white : SfColors.ink),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: SfSpace.xs),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final pressed = loading ? null : onPressed;

    final Widget button = switch (_kind) {
      _Kind.primary => ElevatedButton(onPressed: pressed, child: child),
      _Kind.secondary => FilledButton(onPressed: pressed, child: child),
      _Kind.outline => OutlinedButton(onPressed: pressed, child: child),
      _Kind.text => TextButton(onPressed: pressed, child: child),
      _Kind.destructive => OutlinedButton(
          onPressed: pressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: SfColors.danger,
            side: const BorderSide(color: SfColors.danger),
          ),
          child: child,
        ),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Round icon button on a white disc, for use over images and maps.
class SfCircleButton extends StatelessWidget {
  const SfCircleButton({super.key, required this.icon, required this.onPressed,
      this.tooltip, this.size = 40});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) => Material(
        color: SfColors.surface,
        shape: const CircleBorder(),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip ?? '',
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size * 0.5, color: SfColors.ink),
            ),
          ),
        ),
      );
}
