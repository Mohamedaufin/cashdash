import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../services/storage_service.dart';
import '../services/transaction_service.dart';
import '../services/category_icon_helper.dart';
import '../theme/app_colors.dart';
import 'main_screen.dart';

/// Exact Flutter port of ScannerActivity.kt
/// Gallery QR import, vibrate+beep on scan, payment bottom sheet (native layout),
/// allocation chooser with Create New / Skip / category rows with animated progress.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scannedOnce = false;
  bool _processing = false;

  // Pending transaction state (mirrors native)
  int _pendingAmount = 0;
  String? _pendingCategory;
  bool _isAllocationHandled = false;

  // ── Vibrate (mirrors shake + successBeep) ─────────────────────────────────
  Future<void> _vibrate() async {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  // ── QR detect from live camera ────────────────────────────────────────────
  void _onDetect(BarcodeCapture capture) {
    if (_processing || _scannedOnce) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.contains('upi://pay')) {
        _scannedOnce = true;
        _processing = true;
        _controller.stop();
        _vibrate();
        _showPaymentBottomSheet(code);
        return;
      }
    }
  }

  // ── Gallery: pick image → analyzeImage ────────────────────────────────────
  Future<void> _openGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    
    final bool isScanned = await _controller.analyzeImage(image.path);
    if (!isScanned && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠ No UPI QR found in image')),
      );
    }
  }

  // ── Circular button matching screenshot exactly ─────────────────────────
  Widget _glassBtn({IconData? icon, String? assetIcon, double iconRotation = 0.0, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 15, offset: const Offset(0, 4))
          ],
        ),
        child: Center(
          child: Transform.rotate(
            angle: iconRotation,
            child: assetIcon != null
                ? Image.asset(assetIcon, width: 28, height: 28, fit: BoxFit.contain)
                : Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! < -300) {
            _navigateBackWithSlide(true); // sliding left
          } else if (details.primaryVelocity! > 300) {
            _navigateBackWithSlide(false); // sliding right
          }
        },
        child: Stack(
          children: [
            // Camera
            MobileScanner(controller: _controller, onDetect: _onDetect),

            // Solid cyan scan frame (matches screenshot: no outer glow, solid border, large radius)
            Center(
              child: Container(
                width: 320, 
                height: 320,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00E6FF), width: 4), 
                ),
              ),
            ),

            // Close (top-left) // Matches screenshot close button
            Positioned(
              top: 60,
              left: 25,
              child: _glassBtn(
                icon: Icons.close_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),

            // History (top-right) // Matches screenshot U-Turn left arrow
            Positioned(
              top: 60,
              right: 25,
              child: _glassBtn(
                icon: Icons.undo,
                onTap: _showLastUpi,
              ),
            ),

            // Gallery (bottom-left) // Matches screenshot image icon
            Positioned(
              bottom: 60,
              left: 25,
              child: _glassBtn(
                icon: Icons.image, // Matches the single landscape mountain icon
                onTap: _openGallery,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── History: re-show last scanned UPI ─────────────────────────────────────
  void _showLastUpi() {
    final last = StorageService.getString('last_upi');
    if (last == null || last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous scan history found')),
      );
      return;
    }
    _scannedOnce = true;
    _controller.stop();
    _showPaymentBottomSheet(last);
  }

  // ── Payment bottom sheet (mirrors layout_payment_bottom_sheet.xml) ─────────
  void _showPaymentBottomSheet(String upiUri) {
    StorageService.setString('last_upi', upiUri);

    final params = _parseUpi(upiUri);
    final name = (_uriDecode(params['pn']) ?? 'Unknown').replaceAll('|', '-');
    final id = (_uriDecode(params['pa']) ?? 'Unknown').replaceAll('|', '-');

    _pendingAmount = 0;
    _pendingCategory = null;
    _isAllocationHandled = false;

    final amountController = TextEditingController();
    String? allocationLabel;
    bool paymentContainerVisible = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF060E3A), // Dark blue base
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: EdgeInsets.fromLTRB(
                24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 10),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 25),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
  
                  Text(
                    'Receiver: $name\nUPI ID: $id',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 25),
  
                  // Amount input
                  _glassInputField(amountController, '0',
                      keyboard: TextInputType.number, onChanged: (_) => setSheet(() {})),
                  const SizedBox(height: 25),
  
                  // Allocation section
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          allocationLabel ?? 'No allocation selected',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                      _glass3dSmallButton('Change', () {
                        _showAllocationChooser(
                          onSelected: (cat, label) {
                            setSheet(() {
                              allocationLabel = label;
                              _pendingCategory = cat;
                              _isAllocationHandled = true;
                              paymentContainerVisible = true;
                            });
                          },
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 25),
  
                  // CRED button
                  if (paymentContainerVisible) ...[
                    _glass3dButton(
                      'CRED',
                      onTap: () {
                        _pendingAmount = int.tryParse(amountController.text) ?? 0;
                        Navigator.pop(ctx);
                        _payUpi(upiUri, amountController.text, 'com.dreamplug.androidapp');
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
  
                  // Pay button
                  _glass3dButton(
                    amountController.text.isNotEmpty
                        ? 'Pay ₹${amountController.text}'
                        : 'Pay ₹0',
                    onTap: () {
                      final amt = amountController.text;
                      if (amt.isEmpty || (int.tryParse(amt) ?? 0) == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter an amount')),
                        );
                        return;
                      }
                      if (_pendingCategory == null) {
                        _showAllocationChooser(
                          onSelected: (cat, label) {
                            setSheet(() {
                              allocationLabel = label;
                              _pendingCategory = cat;
                              _isAllocationHandled = true;
                              paymentContainerVisible = true;
                            });
                          },
                        );
                      } else {
                         _pendingAmount = int.tryParse(amountController.text) ?? 0;
                         Navigator.pop(ctx);
                         _payUpi(upiUri, amountController.text, '');
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _scannedOnce = false;
          _processing = false;
        });
        _controller.start();
      }
    });
  }

  // ── Payment bottom sheet helpers ──────────────────────────────────────────

  Widget _glassInputField(TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text,
      ValueChanged<String>? onChanged}) {
    return Container(
      height: 75,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black.withOpacity(0.3),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 22),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _glass3dButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 70,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E3A70), Color(0xFF0A1640)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
            BoxShadow(color: const Color(0xFF3A6AFF).withOpacity(0.15), blurRadius: 15),
          ],
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _glass3dSmallButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.08),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.2),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // ── Allocation chooser (mirrors layout_allocation_chooser_bottom_sheet.xml) ─
  void _showAllocationChooser({
    required void Function(String? cat, String label) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Choose Expense Allocation',
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Create New Allocation
                    _allocationActionButton(
                      '+ Create New Allocation',
                      isRed: false,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCreateCategoryDialog(onSelected: onSelected);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Skip allocation
                    _allocationActionButton(
                      'Skip allocation',
                      isRed: true,
                      onTap: () {
                        Navigator.pop(ctx);
                        onSelected(null, 'No allocation selected');
                      },
                    ),
                    const SizedBox(height: 16),

                    // Categories
                    ...StorageService.categories.map((cat) => _categoryRow(cat, () {
                          Navigator.pop(ctx);
                          onSelected(cat, 'Allocated to: $cat');
                        })),

                    if (StorageService.categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No categories found. Create one first.',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allocationActionButton(String label,
      {required bool isRed, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isRed
                ? const [Color(0xFF6B1515), Color(0xFF300A0A)]
                : const [Color(0xFF1E3A70), Color(0xFF0A1640)],
          ),
          border: Border.all(
              color: isRed
                  ? const Color(0x77FF3333)
                  : const Color(0x444AA3FF),
              width: 1.2),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _categoryRow(String cat, VoidCallback onTap) {
    final double spent = StorageService.getCategorySpent(cat);
    final double limit = StorageService.getCategoryLimit(cat).toDouble();
    final double progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final bool overLimit = limit > 0 && spent >= limit;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white10,
                  ),
                  child: Icon(
                    CategoryIconHelper.getIconForCategory(cat),
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      Text(
                        'Spent: ₹${spent.toInt()}${limit > 0 ? '  Limit: ₹${limit.toInt()}' : '  Limit: —'}',
                        style: TextStyle(
                            color: overLimit ? Colors.redAccent : Colors.white38,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.white.withOpacity(0.2), size: 20),
              ],
            ),
            const SizedBox(height: 10),
            // Animated progress bar (mirrors ScaleAnimation in native)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 500),
                builder: (_, val, __) => LinearProgressIndicator(
                  value: val,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(
                      overLimit ? Colors.redAccent : const Color(0xFF8BF7E6)),
                  minHeight: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Create new category dialog ────────────────────────────────────────────
  void _showCreateCategoryDialog({
    required void Function(String? cat, String label) onSelected,
  }) {
    final nameCtrl = TextEditingController();
    final limitCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Allocation',
            style: TextStyle(color: Colors.white)),
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
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: limitCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Monthly Limit (Optional)',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim().replaceAll('|', '-');
              if (name.isEmpty || name.toLowerCase() == 'overall') {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(name.toLowerCase() == 'overall'
                      ? "Cannot use reserved name 'Overall'"
                      : 'Enter a valid name'),
                ));
                return;
              }
              final limit = int.tryParse(limitCtrl.text.trim()) ?? 0;
              final cats = StorageService.categories;
              if (!cats.contains(name)) {
                cats.add(name);
                StorageService.categories = cats;
                if (limit > 0) StorageService.setCategoryLimit(name, limit);
              }
              Navigator.pop(context);
              onSelected(name, 'Allocated to: $name');
            },
            child: const Text('Create',
                style: TextStyle(color: Color(0xFF8BF7E6))),
          ),
        ],
      ),
    );
  }

  // ── Pay via UPI deep-link (mirrors payUPI in native) ──────────────────────
  // THE ULTIMATE P2P FALLBACK (Bypassing Security Blocks)
  void _payUpi(String originalUri, String amount, String pkg) async {
    final params = _parseUpi(originalUri);
    final paMatch = params['pa'];
    final pnMatch = params['pn'];

    if (paMatch == null || paMatch.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Invalid QR: Missing UPI ID')));
      }
      return;
    }

    final parsedAmt = double.tryParse(amount) ?? 0.0;
    final formattedAmt = parsedAmt.toStringAsFixed(2);

    // Build P2P URI (pa & pn only) precisely like native phase 54
    var p2pUriString = 'upi://pay?pa=$paMatch&am=$formattedAmt&cu=INR';
    if (pnMatch != null && pnMatch.isNotEmpty) {
      p2pUriString += '&pn=$pnMatch';
    }

    final uri = Uri.parse(p2pUriString);

    try {
      // In Flutter, launchUrl(mode: externalApplication) is equivalent to startActivity(Intent.ACTION_VIEW)
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // After launching, record the expense (mirrors redirectSuccess)
        await TransactionService.saveExpense(
          category: _pendingCategory ?? 'no choice',
          amount: _pendingAmount > 0 ? _pendingAmount : (int.tryParse(amount) ?? 0),
          merchant: 'To: ${_uriDecode(pnMatch) ?? 'Unknown'}',
        );
        
        if (mounted) Navigator.pop(context);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('App not installed on this device')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to launch payment app')));
      }
    }
  }

  // ── Util ──────────────────────────────────────────────────────────────────
  Map<String, String> _parseUpi(String uri) {
    final params = <String, String>{};
    if (uri.contains('?')) {
      for (final pair in uri.split('?').last.split('&')) {
        final kv = pair.split('=');
        if (kv.length >= 2) params[kv[0]] = kv.sublist(1).join('=');
      }
    }
    return params;
  }

  String? _uriDecode(String? v) {
    if (v == null) return null;
    try {
      return Uri.decodeComponent(v);
    } catch (_) {
      return v;
    }
  }

  // ── Custom exit animation ───────────────────────────────────────────────
  void _navigateBackWithSlide(bool slideLeft) {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // If the screen slides left (slideLeft = true), the new screen enters from the right (1.0).
          // If the screen slides right, the new screen enters from the left (-1.0).
          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(slideLeft ? 1.0 : -1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
