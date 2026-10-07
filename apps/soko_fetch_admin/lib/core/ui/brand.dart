import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The Soko Fetch mark: a shopping bag with a U-shaped handle cut into it,
/// on an orange rounded square. Same artwork as the launcher icon.
class SokoMark extends StatelessWidget {
  const SokoMark({super.key, this.size = 56, this.inverted = false});

  final double size;

  /// White tile with an orange bag (for orange backgrounds).
  final bool inverted;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: inverted ? SfColors.surface : SfColors.accent,
          borderRadius: BorderRadius.circular(size * 0.26),
        ),
        child: CustomPaint(
          painter: inverted
              ? _BagPainter(SfColors.accent, SfColors.surface)
              : _BagPainter(Colors.white, SfColors.accent),
        ),
      );
}

class _BagPainter extends CustomPainter {
  _BagPainter(this.bag, this.cutout);

  /// The bag, and the colour its handle is cut out in (the tile colour).
  final Color bag;
  final Color cutout;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(s * 0.22, s * 0.30, s * 0.78, s * 0.80),
          Radius.circular(s * 0.07)),
      Paint()..color = bag,
    );
    // Handle: a U cut into the bag, with round ends
    final handle = Paint()
      ..color = cutout
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s * 0.5, s * 0.40), radius: s * 0.12),
      0, 3.14159, false, handle,
    );
    final dot = Paint()..color = cutout;
    canvas.drawCircle(Offset(s * 0.38, s * 0.40), s * 0.045, dot);
    canvas.drawCircle(Offset(s * 0.62, s * 0.40), s * 0.045, dot);
  }

  @override
  bool shouldRepaint(_BagPainter old) => old.bag != bag || old.cutout != cutout;
}

/// "Soko Fetch" wordmark set in the app font.
class SokoWordmark extends StatelessWidget {
  const SokoWordmark({super.key, this.color = SfColors.ink, this.size = 22});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        'Soko Fetch',
        style: Theme.of(context).textTheme.titleLarge!.copyWith(
            color: color, fontSize: size, letterSpacing: -0.4),
      );
}
