import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_numpad.dart';
import '../services/storage_service.dart';
import '../services/firebase_service.dart';

class SetLimitScreen extends StatefulWidget {
  final String categoryName;

  const SetLimitScreen({
    super.key,
    required this.categoryName,
  });

  @override
  State<SetLimitScreen> createState() => _SetLimitScreenState();
}

class _SetLimitScreenState extends State<SetLimitScreen> {
  String _currentAmount = '';

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

  void _saveLimitAndFinish() async {
    final value = int.tryParse(_currentAmount) ?? 0;
    // Native logic: can be 0 or more
    final totalBalance = StorageService.initialBalance;
    var currentSum = 0;
    
    for (final cat in StorageService.categories) {
      if (cat.toLowerCase() != widget.categoryName.toLowerCase()) {
        currentSum += StorageService.getCategoryLimit(cat);
      }
    }
    
    final maxAllowed = totalBalance - currentSum;
    
    if (value > maxAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exceeds total balance! Max allowed: ₹$maxAllowed')),
        );
      }
      setState(() {
        _currentAmount = maxAllowed.toString();
      });
      return;
    }

    StorageService.setCategoryLimit(widget.categoryName, value);
    await FirebaseService.pushAllDataToCloud();
    
    if (mounted) {
      Navigator.pop(context);
    }
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
                    const SizedBox(height: 20),
                    _buildAmountDisplayBox(),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 24),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {}, // Warn logic if needed
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        const Text(
          'Setting limit',
          style: TextStyle(
            color: Colors.white, 
            fontSize: 24, 
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 0), blurRadius: 12),
              Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 0), blurRadius: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAmountDisplayBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(height: 20),
          GlassContainer(
            height: 100,
            borderRadius: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('₹', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                Text(
                  _currentAmount.isEmpty ? '0' : _currentAmount,
                  style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          GestureDetector(
            onTap: _saveLimitAndFinish,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: const Center(
                child: Icon(Icons.arrow_forward, color: Colors.white, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberPad() {
    final totalBalance = StorageService.initialBalance;
    var currentSum = 0;
    for (final cat in StorageService.categories) {
      if (cat.toLowerCase() != widget.categoryName.toLowerCase()) {
        currentSum += StorageService.getCategoryLimit(cat);
      }
    }
    final maxAllowed = (totalBalance - currentSum).clamp(0, totalBalance);
    final val = int.tryParse(_currentAmount) ?? 0;
    final isExceeded = val > maxAllowed;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isExceeded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.white.withAlpha(200),
              child: Text(
                'Exceeds total balance! Max allowed: ₹$maxAllowed',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            )
          else
            const SizedBox(height: 15), // Placeholder for the bar

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: GlassNumpad(
              onNumberTap: _onNumberTap,
              onBackspace: _onBackspace,
              onAction: _saveLimitAndFinish,
              actionIcon: Icons.arrow_forward_ios,
            ),
          ),
        ],
      ),
    );
  }
}
