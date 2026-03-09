import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../services/storage_service.dart';
import '../services/category_icon_helper.dart';
import 'set_limit_screen.dart';

class CategoryAnalysisScreen extends StatefulWidget {
  final String categoryName;
  const CategoryAnalysisScreen({super.key, required this.categoryName});

  @override
  State<CategoryAnalysisScreen> createState() => _CategoryAnalysisScreenState();
}

class _CategoryAnalysisScreenState extends State<CategoryAnalysisScreen> {
  /// Returns the last 4 rolling week totals from stored transactions.
  List<double> _getWeeklyData() {
    final now = DateTime.now();
    // Start of current week (Monday)
    final dayOfWeek = now.weekday; // 1=Mon ... 7=Sun
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: dayOfWeek - 1));

    final w = [0.0, 0.0, 0.0, 0.0]; // w[0]=3 weeks ago, w[3]=this week

    final history = StorageService.rawHistoryEntries;
    for (final entry in history) {
      final parts = entry.split('|');
      if (parts.length < 9) continue;
      final cat = parts[3];
      if (cat != widget.categoryName && widget.categoryName != 'Overall') continue;

      final ts = int.tryParse(parts[1]) ?? 0;
      final amount = double.tryParse(parts[4]) ?? 0.0;
      final msPerWeek = const Duration(days: 7).inMilliseconds;
      final swMs = startOfWeek.millisecondsSinceEpoch;

      if (ts >= swMs) {
        w[3] += amount;
      } else if (ts >= swMs - msPerWeek) {
        w[2] += amount;
      } else if (ts >= swMs - 2 * msPerWeek) {
        w[1] += amount;
      } else if (ts >= swMs - 3 * msPerWeek) {
        w[0] += amount;
      }
    }
    return w;
  }

  List<String> _getWeekLabels() {
    final now = DateTime.now();
    final dayOfWeek = now.weekday;
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: dayOfWeek - 1));

    final labels = <String>[];
    for (int i = 3; i >= 0; i--) {
      final s = startOfWeek.subtract(Duration(days: i * 7));
      final e = s.add(const Duration(days: 6));
      labels.add('${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}');
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final weeklyData = _getWeeklyData();
    final weekLabels = _getWeekLabels();
    final limit = StorageService.getCategoryLimit(widget.categoryName);
    final avg = weeklyData.isNotEmpty
        ? weeklyData.reduce((a, b) => a + b) / weeklyData.length
        : 0.0;
    final maxVal = weeklyData.reduce((a, b) => a > b ? a : b);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.mainBackgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 46,
                      height: 46,
                      margin: const EdgeInsets.only(top: 20),
                      decoration: BoxDecoration(
                        color: AppColors.glassStart,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.glassStroke, width: 1.2),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Previous data analysis',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.categoryName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: AppColors.neonBlue, blurRadius: 12)],
                  ),
                ),
                if (limit > 0) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Limit : ₹$limit',
                    style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 18),
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(color: Color(0x40FFFFFF), indent: 40, endIndent: 40),
                const SizedBox(height: 10),

                // ── Bar Graph ──────────────────────────────────────────────
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _WeeklyBarGraphPainter(
                      data: weeklyData,
                      labels: weekLabels,
                      limit: limit.toDouble(),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
                const Text(
                  'Data analysis from the past 4 weeks',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                  textAlign: TextAlign.center,
                ),

                // ── Average ───────────────────────────────────────────────
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Avg : ', style: TextStyle(color: Colors.white, fontSize: 22)),
                    Text(
                      '₹${avg.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                // ── Info box ──────────────────────────────────────────────
                const SizedBox(height: 30),
                GlassContainer(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: const [
                      Icon(Icons.info, color: Colors.white, size: 32),
                      SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          'The limit you are setting will not block/stop your payment when you exceed it. It is only for tracking purposes.',
                          style: TextStyle(color: Color(0xFFB0C4FF), fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Set Limit button ──────────────────────────────────────
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SetLimitScreen(categoryName: widget.categoryName)),
                      ).then((_) => setState(() {}));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 8,
                    ),
                    child: const Text(
                      'SET LIMIT',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeeklyBarGraphPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final double limit;

  _WeeklyBarGraphPainter({
    required this.data,
    required this.labels,
    required this.limit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double maxVal = [
      limit > 0 ? limit : 0.0,
      ...data,
    ].reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    final double barWidth = size.width / 14.0;
    final double spacing = size.width / (data.length + 1.0);

    final double bottom = size.height - 70.0;
    final double graphHeight = size.height - 110.0;

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw Limit Line
    if (limit > 0) {
      final double ratio = limit / maxVal;
      double limitY = bottom - (ratio * graphHeight);
      limitY = limitY.clamp(20.0, bottom);

      final Paint limitPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(0, limitY), Offset(size.width, limitY), limitPaint);
    }

    for (int i = 0; i < data.length; i++) {
      final double value = data[i];
      final double center = spacing * (i + 1);

      if (value == 0) {
        _drawText(canvas, "₹0", center, bottom - 25.0, textPainter, 12, Colors.white);
        _drawText(canvas, labels[i].split('-').first, center, size.height - 35.0, textPainter, 10, Colors.white38);
        continue;
      }

      double barHeight = (value / maxVal) * graphHeight;
      if (barHeight < 10.0) barHeight = 10.0;

      final double left = center - barWidth / 2;
      final double right = center + barWidth / 2;
      final double top = bottom - barHeight;

      final bool isOverLimit = limit > 0 && value >= limit;
      final Color baseColor = isOverLimit ? const Color(0xFF8BF7E6) : const Color(0xFFD9D9D9);
      final Color darkColor = isOverLimit ? const Color(0xFF4A9F91) : const Color(0xFFA0A0A0);

      // ── 3D Gradient ────────────────────────────────────────────────
      final Rect barRect = Rect.fromLTRB(left, top, right, bottom);
      final Paint barPaint3D = Paint()
        ..shader = LinearGradient(
          colors: [baseColor, darkColor],
        ).createShader(Rect.fromLTRB(left, top, right, top))
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, const Radius.circular(40)),
        barPaint3D,
      );

      // ── Gloss Highlight ─────────────────────────────────────────────
      final Paint glossPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0.4), Colors.transparent],
        ).createShader(Rect.fromLTRB(left, top, right, top + barHeight * 0.4))
        ..isAntiAlias = true;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left + 2, top + 2, right - 2, top + barHeight * 0.4),
          const Radius.circular(40),
        ),
        glossPaint,
      );

      _drawText(canvas, "₹${value.toInt()}", center, top - 20.0, textPainter, 12, Colors.white);
      _drawText(canvas, labels[i].split('-').first, center, size.height - 35.0, textPainter, 10, Colors.white38);
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y, TextPainter tp, double fontSize, Color color) {
    tp.text = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
    );
    tp.layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WeeklyBarGraphPainter old) =>
      old.data != data || old.labels != labels || old.limit != limit;
}
