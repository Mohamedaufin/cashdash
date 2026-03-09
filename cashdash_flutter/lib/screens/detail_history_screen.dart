import 'package:flutter/material.dart';
import 'dart:math';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../services/storage_service.dart';
import '../services/transaction_service.dart';
import '../services/category_icon_helper.dart';
import '../services/firebase_service.dart';
import '../services/history_service.dart';

/// Mirrors DetailHistoryActivity.kt — shows category breakdown pie + transaction list
/// for a specific day, week, or month.
class DetailHistoryScreen extends StatefulWidget {
  final String mode; // DAILY | WEEKLY | MONTHLY
  final int week;
  final int day;
  final int month;
  final int year;

  const DetailHistoryScreen({
    super.key,
    required this.mode,
    required this.week,
    required this.day,
    required this.month,
    required this.year,
  });

  @override
  State<DetailHistoryScreen> createState() => _DetailHistoryScreenState();
}

class _DetailHistoryScreenState extends State<DetailHistoryScreen> {
  late List<TransactionItem> _transactions;
  late Map<String, double> _categoryTotals;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final all = StorageService.rawHistoryEntries;
    final filtered = <TransactionItem>[];
    final totals = <String, double>{};

    for (final raw in all) {
      final p = raw.split('|');
      if (p.length < 9) continue;

      final hWeek = int.tryParse(p[5]) ?? 0;
      final hDay = int.tryParse(p[6]) ?? 0;
      final hMonth = int.tryParse(p[7]) ?? 0;
      final hYear = int.tryParse(p[8]) ?? 0;
      final amount = double.tryParse(p[4]) ?? 0.0;
      final cat = p[3];

      bool match = false;
      if (widget.mode == 'DAILY') {
        match = hYear == widget.year &&
            hMonth == widget.month &&
            hWeek == widget.week &&
            hDay == widget.day;
      } else if (widget.mode == 'WEEKLY') {
        match = hYear == widget.year &&
            hMonth == widget.month &&
            hWeek == widget.week;
      } else {
        match = hYear == widget.year && hMonth == widget.month;
      }

      if (match) {
        filtered.add(TransactionItem(
          title: p[2],
          category: cat,
          amount: amount.toInt(),
          rawEntry: raw,
        ));
        totals[cat] = (totals[cat] ?? 0) + amount;
      }
    }

    // Sort newest first by timestamp in rawEntry[1]
    filtered.sort((a, b) {
      final tsA = int.tryParse(a.rawEntry.split('|').length > 1 ? a.rawEntry.split('|')[1] : '0') ?? 0;
      final tsB = int.tryParse(b.rawEntry.split('|').length > 1 ? b.rawEntry.split('|')[1] : '0') ?? 0;
      return tsB.compareTo(tsA);
    });

    _transactions = filtered;
    _categoryTotals = totals;
  }

  String get _title {
    switch (widget.mode) {
      case 'DAILY':
        return 'Breakdown for Day ${widget.day + 1}';
      case 'WEEKLY':
        return 'Breakdown for Week ${widget.week + 1}';
      default:
        return 'Monthly Breakdown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.mainBackgroundGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.glassStart,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.glassStroke, width: 1.2),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // ── Category Breakdown Bar Chart ─────────────────────────
              const SizedBox(height: 20),
              _buildCategoryGraph(),

              // ── "History" label ──────────────────────────────────────
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 15, 20, 25),
                child: Text('History',
                    style: TextStyle(color: Colors.white, fontSize: 20)),
              ),

              // ── Transaction list ─────────────────────────────────────
              Expanded(
                child: _transactions.isEmpty
                    ? const Center(
                        child: Text('No transactions',
                            style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _transactions.length,
                        itemBuilder: (context, i) =>
                            _buildTransactionItem(_transactions[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryGraph() {
    if (_categoryTotals.isEmpty) {
      return const SizedBox(
        height: 250,
        child: Center(
          child: Text('No data', style: TextStyle(color: Colors.white38)),
        ),
      );
    }

    final categories = _categoryTotals.keys.toList();
    final values = _categoryTotals.values.toList();

    return SizedBox(
      height: 250,
      width: double.infinity,
      child: CustomPaint(
        painter: _CategoryBreakdownPainter(
          categories: categories,
          values: values,
        ),
      ),
    );
  }

  Widget _buildTransactionItem(TransactionItem tx) {
    return GestureDetector(
      onLongPress: () => _showActionMenu(tx),
      child: TransactionGlass(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(width: 4), // Small extra padding for icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CategoryIconHelper.getIconForCategory(tx.category),
                color: Colors.white70,
                size: 22,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.title,
                      style: const TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(tx.category.toUpperCase(),
                      style: const TextStyle(color: Color(0xFFB0C8FF), fontSize: 14)),
                ],
              ),
            ),
            Text(
              '-₹${tx.amount}',
              style: const TextStyle(
                  color: Color(0xFFFF4D4D),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  shadows: [Shadow(color: Color(0x80FF4D4D), blurRadius: 10)]),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionMenu(TransactionItem tx) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: const Color(0xE0050810), // Black Glass
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
        ),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Transaction Options',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _actionButton('Edit Title', AppColors.neonBlue, () => _showEditTitleDialog(tx)),
            const SizedBox(height: 12),
            _actionButton('Edit Amount', AppColors.neonBlue, () => _showEditAmountDialog(tx)),
            const SizedBox(height: 12),
            _actionButton('Reallocate Category', AppColors.neonBlue, () => _showReallocationSheet(tx)),
            const SizedBox(height: 12),
            _actionButton('Delete Transaction', Colors.redAccent, () => _showDeleteConfirmation(tx)),
          ],
        ),
      ),
    );
  }

  void _showEditTitleDialog(TransactionItem tx) {
    final controller = TextEditingController(text: tx.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Title', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter new title',
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () async {
            final newTitle = controller.text.trim();
            if (newTitle.isNotEmpty) {
              Navigator.pop(ctx);
              await TransactionService.updateTransactionTitle(tx, newTitle);
              setState(() => _loadData());
            }
          }, child: const Text('Save')),
        ],
      ),
    );
  }

  void _showEditAmountDialog(TransactionItem tx) {
    final controller = TextEditingController(text: tx.amount.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Amount', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter new amount',
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () async {
            final newAmount = int.tryParse(controller.text) ?? 0;
            if (newAmount > 0) {
              Navigator.pop(ctx);
              await TransactionService.updateTransactionAmount(tx, newAmount);
              setState(() => _loadData());
            }
          }, child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          Navigator.pop(context);
          onTap();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: color.withOpacity(0.5))),
        ),
        child:
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showReallocationSheet(TransactionItem tx) {
    final categoriesList = StorageService.categories
        .where((c) => c != tx.category)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => GlassContainer(
        borderRadius: 30,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reallocate ₹${tx.amount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: categoriesList.length,
                itemBuilder: (_, i) => ListTile(
                  leading: Icon(
                      CategoryIconHelper.getIconForCategory(categoriesList[i]),
                      color: AppColors.neonBlue),
                  title: Text(categoriesList[i],
                      style: const TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    await TransactionService.reallocateTransaction(
                        transaction: tx, newCategory: categoriesList[i]);
                    FirebaseService.pushAllDataToCloud();
                    setState(() => _loadData());
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(TransactionItem tx) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Transaction?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this transaction?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await TransactionService.deleteTransaction(tx);
              FirebaseService.pushAllDataToCloud();
              setState(() => _loadData());
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownPainter extends CustomPainter {
  final List<String> categories;
  final List<double> values;

  _CategoryBreakdownPainter({required this.categories, required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (categories.isEmpty || values.isEmpty) return;

    final double maxVal = values.isEmpty ? 1.0 : values.reduce(max).toDouble().clamp(1.0, double.infinity);

    final double barWidth = size.width / 14.0;
    final double spacing = size.width / (values.length + 1.0);

    final double bottom = size.height - 70.0;
    final double graphHeight = size.height - 110.0;

    final Paint barPaint = Paint()
      ..color = const Color(0xFFD9D9D9)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (int i = 0; i < values.length; i++) {
      final double value = values[i];
      final double center = spacing * (i + 1);

      if (value == 0) {
        _drawText(canvas, "₹0", center, bottom - 25.0, textPainter, 12, Colors.white);
        _drawText(canvas, categories[i], center, size.height - 70.0, textPainter, 12, Colors.white);
        continue;
      }

      double barHeight = (value / maxVal) * graphHeight;
      if (barHeight < 10.0) barHeight = 10.0;

      final double left = center - barWidth / 2;
      final double right = center + barWidth / 2;
      final double top = bottom - barHeight;

      // ── 3D Gradient ────────────────────────────────────────────────
      final Rect barRect = Rect.fromLTRB(left, top, right, bottom);
      final Paint barPaint3D = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFD9D9D9), Color(0xFFA0A0A0)],
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
      _drawText(canvas, categories[i], center, size.height - 70.0, textPainter, 12, Colors.white);
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
  bool shouldRepaint(covariant _CategoryBreakdownPainter old) =>
      old.categories != categories || old.values != values;
}
