import 'dart:math';
import 'package:flutter/material.dart';

/// Mirrors GradientCircularProgressView.kt from the native Android app.
/// Draws: dark track ring → shadow arc → gradient arc, with round caps.
class GradientCircularProgress extends StatefulWidget {
  final double progress; // 0..100
  final bool animate;
  final double strokeWidth;

  const GradientCircularProgress({
    super.key,
    required this.progress,
    this.animate = true,
    this.strokeWidth = 22.0,
  });

  @override
  State<GradientCircularProgress> createState() => _GradientCircularProgressState();
}

class _GradientCircularProgressState extends State<GradientCircularProgress>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0, end: widget.progress).animate(
      CurvedAnimation(parent: _controller, curve: const Cubic(0.25, 0.1, 0.25, 1.0)), // Decelerate(1.5) approx
    )..addListener(() => setState(() {}));

    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant GradientCircularProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.progress,
      ).animate(CurvedAnimation(parent: _controller, curve: const Cubic(0.25, 0.1, 0.25, 1.0)));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GradientArcPainter(
        progress: widget.animate ? _animation.value : widget.progress,
        strokeWidth: widget.strokeWidth,
      ),
    );
  }
}

class _GradientArcPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;

  _GradientArcPainter({required this.progress, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final effectiveStrokeWidth = 45.0; // Exact native parity (45dp)
    final radius = (min(size.width, size.height) / 2) - effectiveStrokeWidth / 2 - 20; 
    const startAngle = -pi / 2;

    // ── 1. Background track ring ──────────────────────────────────────────
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = effectiveStrokeWidth
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF08123A); // Exact native track color
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final sweepAngle = (progress.clamp(0.0, 100.0) / 100.0) * 2 * pi;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // ── 2. Glow / shadow arc (REMOVED) ───────────────────────────────────

    // ── 3. Gradient arc ───────────────────────────────────────────────────
    final bool isLow = progress <= 15;
    final List<Color> colors = isLow
        ? [
            const Color(0xFFFF0033), // Deep Red
            const Color(0xFFFF5C00), // Intense Orange
            const Color(0xFFFF0033),
            const Color(0xFFFF5C00),
            const Color(0xFFFF0033),
          ]
        : [
            const Color(0xFF00E5FF), // Neon Cyan
            const Color(0xFF4AA3FF), // Sky Blue
            const Color(0xFFB65CFF), // Purple
            const Color(0xFFFF007A), // Hot Pink
            const Color(0xFF00E5FF), // Loop
          ];

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = effectiveStrokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: colors,
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: const GradientRotation(-pi / 2),
      ).createShader(arcRect);

    canvas.drawArc(arcRect, startAngle, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _GradientArcPainter old) =>
      old.progress != progress || old.strokeWidth != strokeWidth;
}
