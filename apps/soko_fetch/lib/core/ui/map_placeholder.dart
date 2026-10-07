import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Stands in for a map when Google Maps isn't configured
/// (AppConfig.mapsEnabled): a soft street-grid pattern with a pin.
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({super.key, this.icon = Icons.location_on_rounded});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        color: SfColors.surface2,
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _GridPainter()),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: SfColors.surface,
                shape: BoxShape.circle,
                boxShadow: SfShadow.floating,
              ),
              child: Icon(icon, color: SfColors.accentStrong, size: 30),
            ),
          ),
        ]),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = SfColors.surface3
      ..strokeWidth = 1;
    final major = Paint()
      ..color = SfColors.surface
      ..strokeWidth = 10;
    for (var x = -size.height; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height * 0.4, 0), minor);
    }
    for (var y = 24.0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 18), minor);
    }
    canvas.drawLine(Offset(0, size.height * 0.62),
        Offset(size.width, size.height * 0.38), major);
    canvas.drawLine(Offset(size.width * 0.3, 0),
        Offset(size.width * 0.45, size.height), major);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
