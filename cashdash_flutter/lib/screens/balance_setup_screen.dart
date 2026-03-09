import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_numpad.dart';
import '../services/storage_service.dart';
import '../services/firebase_service.dart';
import 'main_screen.dart';

class BalanceSetupScreen extends StatefulWidget {
  const BalanceSetupScreen({super.key});

  @override
  State<BalanceSetupScreen> createState() => _BalanceSetupScreenState();
}

class _BalanceSetupScreenState extends State<BalanceSetupScreen> {
  String _currentAmount = '';
  late bool _isFirstTime;

  @override
  void initState() {
    super.initState();
    _isFirstTime = StorageService.initialBalance == 0;
  }

  void _onNumberTap(String value) {
    if (_currentAmount.length < 9) {
      setState(() {
        if (_currentAmount == '0') {
          _currentAmount = value;
        } else {
          _currentAmount += value;
        }
      });
    }
  }

  void _onBackspace() {
    if (_currentAmount.isNotEmpty) {
      setState(() {
        _currentAmount = _currentAmount.substring(0, _currentAmount.length - 1);
      });
    }
  }

  void _onCancel() {
    setState(() {
      _currentAmount = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    const SizedBox(height: 35),
                    _buildHeader(),
                    const SizedBox(height: 15),
                    Text(
                      'Current balance: ₹${StorageService.walletBalance}',
                      style: const TextStyle(color: AppColors.lightBlueText, fontSize: 16),
                    ),
                    const SizedBox(height: 15),
                    _buildAmountDisplay(),
                    const SizedBox(height: 30),
                    _buildActionButtons(),
                    const SizedBox(height: 40),
                    _buildNumberPad(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.glassStart,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.glassStroke, width: 1.2),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              ),
            ),
          ),
          const Text(
            'Wallet balance',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 2), blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: GlassContainer(
        height: 100,
        borderRadius: 14,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('₹', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Text(
              _currentAmount.isEmpty ? '0' : _currentAmount,
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  'Add to current balance',
                  onTap: () => _handleUpdate(isReplace: false),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildActionButton(
                  'Replace total balance',
                  onTap: () => _handleUpdate(isReplace: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose how to update your wallet balance',
            style: TextStyle(color: Color(0xFFB0C8FF), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        height: 65,
        borderRadius: 14,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: GlassNumpad(
        onNumberTap: _onNumberTap,
        onBackspace: _onBackspace,
        onAction: _onCancel,
        actionIcon: Icons.close,
      ),
    );
  }

  void _handleUpdate({required bool isReplace}) async {
    final amount = int.tryParse(_currentAmount) ?? 0;
    if (amount <= 0) return;

    final oldBalance = StorageService.walletBalance;
    final oldInitial = StorageService.initialBalance;

    if (isReplace) {
      StorageService.walletBalance = amount;
      StorageService.initialBalance = amount;
    } else {
      StorageService.walletBalance = oldBalance + amount;
      StorageService.initialBalance = oldInitial + amount;
    }

    await FirebaseService.pushAllDataToCloud();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context, 
        MaterialPageRoute(builder: (_) => const MainScreen()), 
        (route) => false
      );
    }
  }
}
