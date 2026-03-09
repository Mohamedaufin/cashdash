import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../components/gradient_circular_progress.dart';
import '../services/storage_service.dart';
import '../services/firebase_service.dart';
import 'scanner_screen.dart';
import 'history_screen.dart';
import 'allocator_screen.dart';
import 'profile_screen.dart';
import 'rigor_screen.dart';
import 'rigor_screen.dart';
import 'package:flutter/services.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/glass_menu_icon.dart';
import 'success_screen.dart';

import 'home_content.dart';

class MainScreen extends StatefulWidget {
  final int startTab;
  const MainScreen({super.key, this.startTab = 1});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  static const platform = MethodChannel('com.aufin.cashdash/payment_channel');
  late PageController _pageController;
  bool _scannerOpened = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.startTab;
    _pageController = PageController(initialPage: _selectedIndex);
    _checkPendingPayment();
    platform.setMethodCallHandler(_handleMethodCall);
    
    // 🔥 Ported updateNextMoneyDays logic from MainActivity.kt
    _updateNextMoneyDays();

    // Auto-open scanner if it's the 4th tab (virtual) or requested
    if (widget.startTab == 3) {
      _selectedIndex = 1;
      _pageController = PageController(initialPage: 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scannerOpened) {
          _scannerOpened = true;
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _updateNextMoneyDays() {
    final nextMs = StorageService.nextDateMs;
    final freq = StorageService.frequency;

    if (nextMs == 0) return;

    DateTime next = DateTime.fromMillisecondsSinceEpoch(nextMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextDateOnly = DateTime(next.year, next.month, next.day);

    if (today.isAfter(nextDateOnly)) {
      final isInitialized = StorageService.cycleInitialized;

      // Auto roll forward cycle
      while (next.isBefore(today) || next.isAtSameMomentAs(today)) {
        next = next.add(Duration(days: freq));
      }
      StorageService.nextDateMs = next.millisecondsSinceEpoch;

      if (isInitialized) {
        // 🔄 Cycle Renewed!
        // 1. Replenish wallet balance
        StorageService.walletBalance = StorageService.initialBalance;

        // 2. Reset category spent amounts
        for (var cat in StorageService.categories) {
          StorageService.setCategorySpent(cat, 0.0);
        }

        // 3. Sync to cloud
        FirebaseService.pushAllDataToCloud();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Cycle renewed! tentatively till ${next.day}/${next.month}/${next.year}"),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        // Mark as initialized for future rollovers
        StorageService.cycleInitialized = true;
      }
    }
  }

  Future<void> _checkPendingPayment() async {
    try {
      final String? result = await platform.invokeMethod('checkPendingPaymentResult');
      if (result != null && mounted) {
        _showSuccessPopup(result);
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to check pending payment: '${e.message}'.");
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onPaymentDetected') {
      final String result = call.arguments as String;
      if (mounted) {
        _showSuccessPopup(result);
      }
    }
  }

  void _showSuccessPopup(String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (BuildContext buildContext, Animation animation, Animation secondaryAnimation) {
        return SuccessScreen(message: message);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: Stack(
          children: [
            // Using IndexedStack for seamless tab switching with icon highlighting
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Match native where you click tabs
              onPageChanged: (index) {
                setState(() => _selectedIndex = index);
              },
              children: [
                const AllocatorScreen(),
                HomeContent(scaffoldKey: _scaffoldKey),
                const HistoryScreen(),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassBottomNavBar(
                selectedIndex: _selectedIndex,
                onTabSelected: (index) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
