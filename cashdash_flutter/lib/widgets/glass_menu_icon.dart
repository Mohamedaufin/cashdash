import 'package:flutter/material.dart';

/// Exact Flutter replica of `ic_glass_menu_vector.xml`.
/// 3 rounded bars, each with a 50% white frosted body + bright white rim highlight.
class GlassMenuIcon extends StatelessWidget {
  final double size;

  const GlassMenuIcon({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GlassMenuPainter()),
    );
  }
}

class _GlassMenuPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Scale from 24x24 viewport to actual widget size
    final double scaleX = size.width / 24;
    final double scaleY = size.height / 24;

    // Bar definitions: [top-y, height] in the 24x24 viewport
    const bars = [
      [6.0, 2.5],  // Bar 1
      [11.0, 2.5], // Bar 2
      [16.0, 2.5], // Bar 3
    ];

    const double barLeft = 3.0;
    const double barRight = 21.0; // 3 + 18
    const double rimHeight = 0.5;
    const double cornerRadius = 1.25; // Matches the 2.5dp height ÷ 2 roughly

    final bodyPaint = Paint()
      ..color = const Color(0x80FFFFFF)  // 50% white — frosted glass body
      ..style = PaintingStyle.fill;

    final rimPaint = Paint()
      ..color = const Color(0xE0FFFFFF)  // bright rim highlight
      ..style = PaintingStyle.fill;

    for (final bar in bars) {
      final double top = bar[0] * scaleY;
      final double barH = bar[1] * scaleY;
      final double left = barLeft * scaleX;
      final double right = barRight * scaleX;
      final double rim = rimHeight * scaleY;
      final double rad = cornerRadius * scaleY;

      // Body rect (50% white)
      final bodyRect = Rect.fromLTWH(left, top, right - left, barH);
      canvas.drawRect(bodyRect, bodyPaint);

      // Rim highlight (bright white, top strip)
      final rimRect = Rect.fromLTWH(left, top, right - left, rim);
      canvas.drawRect(rimRect, rimPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
