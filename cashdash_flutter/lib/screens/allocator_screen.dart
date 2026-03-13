import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../services/storage_service.dart';
import '../services/category_icon_helper.dart';
import '../services/firebase_service.dart';
import '../widgets/bottom_nav_bar.dart';
import 'history_screen.dart';
import 'main_screen.dart';
import 'category_analysis_screen.dart';
import 'set_limit_screen.dart';
import '../widgets/three_d_dropdown.dart';
import '../theme/app_styles.dart';
import '../components/transaction_dialog.dart';
import '../components/glass_input.dart';
import '../components/glass_button.dart';

class AllocatorScreen extends StatefulWidget {
  const AllocatorScreen({super.key});

  @override
  State<AllocatorScreen> createState() => _AllocatorScreenState();
}

class _AllocatorScreenState extends State<AllocatorScreen> {
  String? _lastDeletedCategory;
  int? _lastDeletedIndex;

  void _restoreCategory() {
    if (_lastDeletedCategory != null && _lastDeletedIndex != null) {
      final cats = StorageService.categories;
      if (!cats.contains(_lastDeletedCategory!)) {
        if (_lastDeletedIndex! < cats.length) {
          cats.insert(_lastDeletedIndex!, _lastDeletedCategory!);
        } else {
          cats.add(_lastDeletedCategory!);
        }
        StorageService.categories = cats;
        FirebaseService.pushAllDataToCloud();
        setState(() {
          _lastDeletedCategory = null;
          _lastDeletedIndex = null;
        });
      }
    }
  }
  Future<bool?> _showDeleteConfirmation(String name) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => TransactionDialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              'Delete Allocation',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Are you sure you want to delete "$name"? This action cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    isSecondary: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassButton(
                    label: 'Delete',
                    color: Colors.redAccent,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final categories = StorageService.categories;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 50),
                _buildHeader(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 140), // Include nav bar space here
                    itemCount: categories.length + 1,
                    itemBuilder: (context, index) {
                      if (index == categories.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 0),
                          child: _buildAddButton(),
                        );
                      }
                      return _buildCategoryCard(categories[index]);
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassBottomNavBar(
                selectedIndex: 0,
                scrollPosition: 0.0,
                onTabSelected: (index) {
                  if (index == 1) {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
                  } else if (index == 2) {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_lastDeletedCategory == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _restoreCategory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF42A5F5).withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.restore, color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'RESTORE',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCategoryCard(String cat) {
    final double limit = StorageService.getCategoryLimit(cat).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 25), 
      child: Dismissible(
        key: Key(cat),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          return await _showDeleteConfirmation(cat);
        },
        background: const SizedBox.shrink(), // Natural swipe, no red background
        secondaryBackground: const SizedBox.shrink(),
        onDismissed: (_) {
          final cats = StorageService.categories;
          final index = cats.indexOf(cat);
          setState(() {
            _lastDeletedCategory = cat;
            _lastDeletedIndex = index;
          });
          cats.removeAt(index);
          StorageService.categories = cats;
          FirebaseService.pushAllDataToCloud();
        },
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CategoryAnalysisScreen(categoryName: cat)),
            );
          },
          onLongPress: () => _showRenameDialog(cat),
          child: Container(
            constraints: const BoxConstraints(minHeight: 110),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: const Color(0xFF19286F),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              children: [
                // Icon Area
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C144E),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Icon(
                      CategoryIconHelper.getIconForCategory(cat),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 26),
                // Text Area
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Limit : ₹${limit.toInt()}',
                        style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Button
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SetLimitScreen(categoryName: cat)),
                    ).then((_) => setState(() {}));
                  },
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50), 
                      border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
                      gradient: LinearGradient(
                        colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.03)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    ),
                    child: const Center(
                      child: Text(
                        'Set limit',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: GestureDetector(
        onTap: _showAddCategoryDialog,
        child: Container(
          constraints: const BoxConstraints(minHeight: 110),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF19286F),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              // Icon Area
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C144E),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: Icon(Icons.add, color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(width: 26),
              const Text(
                'Add new',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(String oldName) {
  final controller = TextEditingController(text: oldName);
  showDialog(
    context: context,
    builder: (context) => TransactionDialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Rename Category',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            GlassInput(
              controller: controller,
              hintText: 'New Name',
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    isSecondary: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassButton(
                    label: 'Rename',
                    isSecondary: true,
                    onTap: () {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty && newName != oldName) {
                        final cats = StorageService.categories;
                        final index = cats.indexOf(oldName);
                        if (index != -1) {
                          StorageService.renameCategoryData(oldName, newName);
                          cats[index] = newName;
                          StorageService.categories = cats;
                          FirebaseService.pushAllDataToCloud();
                          setState(() {});
                        }
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  void _showAddCategoryDialog() {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => TransactionDialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add Category',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            GlassInput(
              controller: controller,
              hintText: 'Enter category name',
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    isSecondary: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassButton(
                    label: 'Add',
                    isSecondary: true,
                    onTap: () {
                      final name = controller.text.trim().replaceAll('|', '-');
                      if (name.isNotEmpty) {
                        final cats = StorageService.categories;
                        if (name.toLowerCase() == 'overall') {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("'Overall' is a reserved name")));
                          return;
                        }
                        if (!cats.contains(name)) {
                          cats.add(name);
                          StorageService.categories = cats;
                          FirebaseService.pushAllDataToCloud();
                          setState(() {});
                        }
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}
