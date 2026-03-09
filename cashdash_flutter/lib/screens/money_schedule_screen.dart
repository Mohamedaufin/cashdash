import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_container.dart';
import '../services/storage_service.dart';
import '../services/firebase_service.dart';

class MoneyScheduleScreen extends StatefulWidget {
  const MoneyScheduleScreen({super.key});

  @override
  State<MoneyScheduleScreen> createState() => _MoneyScheduleScreenState();
}

class _MoneyScheduleScreenState extends State<MoneyScheduleScreen> {
  int _frequency = StorageService.frequency;
  DateTime _nextDate = StorageService.nextDateMs > 0 
      ? DateTime.fromMillisecondsSinceEpoch(StorageService.nextDateMs)
      : DateTime.now();
  final _customController = TextEditingController();
  bool _isCustom = false;

  @override
  void initState() {
    super.initState();
    if (_frequency != 7 && _frequency != 30) {
      _isCustom = true;
      _customController.text = _frequency.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Until when is this tentative money for?',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),
                      GlassContainer(
                        padding: const EdgeInsets.all(10),
                        borderRadius: 15,
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
                            initialDate: _nextDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            onDateChanged: (date) => setState(() => _nextDate = date),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      const Text(
                        'How often do you receive money?',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),
                      _buildFrequencySection(),
                      const SizedBox(height: 25),
                      _buildSaveButton(),
                    ],
                  ),
                ),
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
                color: AppColors.glassStart,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassStroke, width: 1.2),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Money Schedule',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildFrequencySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRadio(30, 'Monthly (30 days)'),
        _buildRadio(7, 'Weekly (7 days)'),
        _buildCustomRadio(),
      ],
    );
  }

  Widget _buildRadio(int value, String label) {
    return RadioListTile<int>(
      value: value,
      groupValue: _isCustom ? -1 : _frequency,
      onChanged: (val) {
        setState(() {
          _isCustom = false;
          _frequency = val!;
        });
      },
      title: Text(label, style: const TextStyle(color: Colors.white)),
      activeColor: AppColors.neonBlue,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildCustomRadio() {
    return Column(
      children: [
        RadioListTile<int>(
          value: 0,
          groupValue: _isCustom ? 0 : -1,
          onChanged: (val) {
            setState(() {
              _isCustom = true;
            });
          },
          title: const Text('Custom (Days)', style: TextStyle(color: Colors.white)),
          activeColor: AppColors.neonBlue,
          contentPadding: EdgeInsets.zero,
        ),
        if (_isCustom)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              borderRadius: 12,
              child: TextField(
                controller: _customController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Enter numbers of days',
                  hintStyle: TextStyle(color: Color(0xFFB0B0B0)),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _handleSave,
      child: GlassContainer(
        height: 65,
        borderRadius: 12,
        child: const Center(
          child: Text('Save Schedule', style: TextStyle(color: Colors.white, fontSize: 22)),
        ),
      ),
    );
  }

  void _handleSave() async {
    int freq = _frequency;
    if (_isCustom) {
      freq = int.tryParse(_customController.text) ?? 0;
      if (freq <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid custom days')));
        return;
      }
    }

    // Auto-roll forward logic
    DateTime next = DateTime(_nextDate.year, _nextDate.month, _nextDate.day);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (next.isBefore(todayDate)) {
      while (next.isBefore(todayDate)) {
        next = next.add(Duration(days: freq));
      }
    }

    StorageService.frequency = freq;
    StorageService.nextDateMs = next.millisecondsSinceEpoch;

    await FirebaseService.pushAllDataToCloud();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule updated!')));
      Navigator.pop(context);
    }
  }
}
