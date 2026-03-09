import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

class HistoryGraph extends StatelessWidget {
  final String mode;
  final List<double> values;
  final List<String> labels;
  final int selectedIndex;
  final Function(int)? onBarTap;

  const HistoryGraph({
    super.key,
    required this.mode,
    required this.values,
    required this.labels,
    required this.selectedIndex,
    this.onBarTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) {
        if (onBarTap == null) return;
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        
        final double barWidth = (box.size.width / values.length) * 0.6;
        final double spacing = (box.size.width / values.length) * 0.4;
        final double startX = spacing / 2;

        for (int i = 0; i < values.length; i++) {
          final double x = startX + i * (barWidth + spacing);
          if (localPosition.dx >= x - (spacing/2) && localPosition.dx <= x + barWidth + (spacing/2)) {
            onBarTap!(i);
            break;
          }
        }
      },
      child: CustomPaint(
        size: const Size(double.infinity, 200),
        painter: HistoryPainter(
          values: values,
          labels: labels,
          selectedIndex: selectedIndex,
        ),
      ),
    );
  }
}

class HistoryPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final int selectedIndex;

  HistoryPainter({
    required this.values,
    required this.labels,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double maxVal = values.isEmpty ? 0 : values.reduce(max).toDouble();
    final double adjustedMax = maxVal <= 0 ? 100 : maxVal * 1.2;

    final double barWidth = (size.width / values.length) * 0.6;
    final double spacing = (size.width / values.length) * 0.4;
    final double startX = spacing / 2;

    final Paint barPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.neonBlue, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final Paint selectedPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white10],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final TextPainter textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );

    for (int i = 0; i < values.length; i++) {
      final double barHeight = (values[i] / adjustedMax) * (size.height - 40);
      final double x = startX + i * (barWidth + spacing);
      final double y = size.height - 40 - barHeight;

      final Rect rect = Rect.fromLTWH(x, y, barWidth, barHeight);
      final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));

      // 1. Draw Background (Outer Shell)
      final Paint outerPaint = Paint()
        ..color = const Color(0x10FFFFFF)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, outerPaint);

      final Paint outerStroke = Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(rrect, outerStroke);

      if (values[i] > 0) {
        // 2. Draw Fill
        final Paint fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF80A0FF), Color(0xFF4060DD)],
          ).createShader(rect);
        canvas.drawRRect(rrect, fillPaint);

        // 3. Draw Gloss Highlight
        const double glossPadding = 2.0;
        final Rect glossRect = Rect.fromLTWH(
          x + glossPadding,
          y,
          barWidth - (glossPadding * 2),
          barHeight > 10 ? barHeight - 10 : barHeight,
        );
        final RRect glossRRect = RRect.fromRectAndCorners(
          glossRect,
          topLeft: const Radius.circular(28),
          topRight: const Radius.circular(28),
        );
        final Paint glossPaint = Paint()
          ..style = PaintingStyle.fill
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x60FFFFFF), Color(0x00FFFFFF)],
          ).createShader(glossRect);
        canvas.drawRRect(glossRRect, glossPaint);
      }

      // Highlight the selected bar
      if (i == selectedIndex) {
        final Paint shadowPaint = Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10);
        canvas.drawRRect(rrect, shadowPaint);
      }

      // Label (dd/MM)
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: i == selectedIndex ? FontWeight.bold : FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + (barWidth - textPainter.width) / 2, size.height - 25),
      );

      // 4. Draw Amount Label (White) above the bar
      final amountValue = values[i];
      final amountText = "₹${NumberFormat.compact().format(amountValue)}";
      textPainter.text = TextSpan(
        text: amountText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + (barWidth - textPainter.width) / 2, y - 20),
      );
    }

    // Horizontal grid line (bottom)
    final Paint linePaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 40),
      Offset(size.width, size.height - 40),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant HistoryPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.selectedIndex != selectedIndex;
  }
}
