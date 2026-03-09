import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/storage_service.dart';
import '../services/category_icon_helper.dart';
import '../services/transaction_service.dart';
import '../services/firebase_service.dart';

/// Mirrors activity_rigor.xml + RigorActivity.kt.
/// Page 1: Title input + Amount input + CalendarView → Next
/// Page 2: Category list → tap to save expense
class RigorScreen extends StatefulWidget {
  const RigorScreen({super.key});

  @override
  State<RigorScreen> createState() => _RigorScreenState();
}

class _RigorScreenState extends State<RigorScreen> {
  int _currentPage = 1; // 1 = input, 2 = category
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // ── Shared glass input field matching bg_glass_input ─────────────────────
  Widget _glassInput(TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text}) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x1A4AA3FF),
        border: Border.all(color: const Color(0x334AA3FF), width: 1),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFA8B5D1)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          border: InputBorder.none,
        ),
      ),
    );
  }

  // ── Glass 3D button matching bg_glass_3d drawable ────────────────────────
  Widget _glass3dButton(String label, VoidCallback onTap) {
    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.only(top: 15),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E3A70), Color(0xFF0A1640)],
            ),
            border: Border.all(color: const Color(0x444AA3FF), width: 1.2),
            boxShadow: const [
              BoxShadow(color: Color(0x44000000), blurRadius: 8, offset: Offset(0, 4)),
              BoxShadow(color: Color(0x224AA3FF), blurRadius: 12),
            ],
          ),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.mainBackgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              // ── Page content ──────────────────────────────────────────
              Expanded(
                child: _currentPage == 1 ? _buildPage1() : _buildPage2(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Rigor Tracker',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  // ── PAGE 1: Amount + Title + Calendar ────────────────────────────────────
  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Keep Track of Expenses',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            'Enter the details below to log your expense.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 10),

          // Title input
          _glassInput(_titleController, 'Title of Expense (e.g. Lunch)'),

          // Amount input
          _glassInput(_amountController, 'Enter amount (₹)',
              keyboard: TextInputType.number),

          // Date label
          const Padding(
            padding: EdgeInsets.only(top: 25, bottom: 12),
            child: Text('Select Expense Date',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),

          // Calendar — glass box
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F174A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.2),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AppColors.neonBlue,
                  onPrimary: Colors.white,
                  surface: Colors.transparent,
                  onSurface: Colors.white,
                ),
              ),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                onDateChanged: (date) => setState(() => _selectedDate = date),
              ),
            ),
          ),

          const SizedBox(height: 25),
          // Next button
          _glass3dButton('Next', _goToPage2),
        ],
      ),
    );
  }

  void _goToPage2() {
    if (_titleController.text.trim().isEmpty || _amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }
    setState(() => _currentPage = 2);
  }

  // ── PAGE 2: Category chooser ─────────────────────────────────────────────
  Widget _buildPage2() {
    final categories = StorageService.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        // Heading
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Choose Expense Allocation',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        // Category list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              // 🔥 Create New Allocation Button (Parity with RigorActivity.kt)
              _glass3dButton('+ Create New Allocation', _showCreateCategoryDialog),
              const SizedBox(height: 15),
              ...categories.map((cat) => _buildCategoryTile(cat)),
            ],
          ),
        ),
        // Back button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _glass3dButton('Back', () => setState(() => _currentPage = 1)),
        ),
      ],
    );
  }

  Widget _buildCategoryTile(String cat) {
    final double spent = StorageService.getCategorySpent(cat);
    final double limit = StorageService.getCategoryLimit(cat).toDouble();
    final double progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final bool overLimit = limit > 0 && spent >= limit;

    return GestureDetector(
      onTap: () => _savExpense(cat),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0x1A4AA3FF),
          border: Border.all(color: const Color(0x334AA3FF), width: 1),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12), color: Colors.white10),
                  child: Icon(CategoryIconHelper.getIconForCategory(cat),
                      color: Colors.white70, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        'Spent: ₹${spent.toInt()}${limit > 0 ? '  Limit: ₹${limit.toInt()}' : '  Limit: —'}',
                        style: TextStyle(
                            color: overLimit ? Colors.redAccent : Colors.white38,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            // Progress Bar (Parity with RigorActivity.kt anim)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation(
                    overLimit ? Colors.redAccent : const Color(0xFF8BF7E6)),
                minHeight: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateCategoryDialog() {
    final nameCtrl = TextEditingController();
    final limitCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Allocation', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Category Name (e.g. Travel)',
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: limitCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Monthly Limit (Optional)',
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim().replaceAll('|', '-');
              if (name.isEmpty || name.toLowerCase() == 'overall') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(name.toLowerCase() == 'overall' ? "'Overall' is reserved" : "Enter a name"))
                );
                return;
              }

              final limit = int.tryParse(limitCtrl.text.trim()) ?? 0;
              final totalBalance = StorageService.initialBalance;
              
              // Validation: Check if new limit exceeds total balance
              int currentSumOfLimits = 0;
              for (var cat in StorageService.categories) {
                currentSumOfLimits += StorageService.getCategoryLimit(cat);
              }

              if (limit > (totalBalance - currentSumOfLimits)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Exceeds total balance! Max allowed: ₹${totalBalance - currentSumOfLimits}"))
                );
                return;
              }

              // Save
              final cats = StorageService.categories;
              if (!cats.contains(name)) {
                cats.add(name);
                StorageService.categories = cats;
                if (limit > 0) StorageService.setCategoryLimit(name, limit);
                
                FirebaseService.pushAllDataToCloud();
                setState(() {}); // Refresh list
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create', style: TextStyle(color: Color(0xFF8BF7E6), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _savExpense(String cat) async {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) return;

    // Fixed: Deducting balance is handled inside TransactionService.saveExpense
    // Do not deduct here to avoid double deduction.

    await TransactionService.saveExpense(
      category: cat,
      amount: amount,
      merchant: _titleController.text.trim(),
      date: _selectedDate,
    );
    // pushAllDataToCloud is also handled in TransactionService.saveExpense
    
    if (mounted) Navigator.pop(context);
  }
}
