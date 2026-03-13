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
        size: const Size(double.infinity, 300),
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

    final double barValuesCount = values.length.toDouble();
    final double availableWidth = size.width;
    // Native: spacing = availableWidth / (barValues.size + 1f)
    final double spacing = availableWidth / (barValuesCount + 1);
    // Native: barWidth = availableWidth / 14f
    final double barWidth = availableWidth / 14;

    final Paint barPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final TextPainter textPainter = TextPainter(
      textDirection: ui.TextDirection.ltr,
    );

    const double bottom = 270.0; // Fixed bottom for bars
    const double graphHeight = 200.0; // Max height for bars

    for (int i = 0; i < values.length; i++) {
      final double value = values[i];
      // Native: center = paddingLeft + (spacing * (i + 1))
      final double center = spacing * (i + 1);
      final bool isHighlighted = (i == selectedIndex);

      if (value == 0) {
        // Label (₹0) matches native drawText("₹0", center, bottom - 30f, textPaint)
        textPainter.text = const TextSpan(
          text: "₹0",
          style: TextStyle(
            color: Colors.white,
            fontSize: 14, // Roughly 38f in native
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(center - textPainter.width / 2, bottom - 35));
      } else {
        final double barHeight = (value / adjustedMax * graphHeight).clamp(25.0, graphHeight);
        final double left = center - barWidth / 2;
        final double top = bottom - barHeight;

        final Rect rect = Rect.fromLTWH(left, top, barWidth, barHeight);
        // Native: canvas.drawRoundRect(RectF(left, top, right, bottom), 40f, 40f, barPaint)
        final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(40));

        // Use native colors: #FFC107 for highlighted, #D9D9D9 for normal
        barPaint.color = isHighlighted ? const Color(0xFFFFC107) : const Color(0xFFD9D9D9);
        canvas.drawRRect(rrect, barPaint);

        // Amount Label (₹Value)
        final amountText = "₹${value.toInt()}";
        textPainter.text = TextSpan(
          text: amountText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14, // Roughly 42f in native
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(center - textPainter.width / 2, top - 25));
      }

      // X-Axis Label - Positioned below the baseline
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          color: Colors.white,
          fontSize: labels[i].length > 5 ? 11 : 12,
          fontWeight: FontWeight.normal,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(center - textPainter.width / 2, bottom + 15));
    }

    // Horizontal grid line (baseline) removed for native parity
  }

  @override
  bool shouldRepaint(covariant HistoryPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.selectedIndex != selectedIndex;
  }
}
