import 'package:flutter/material.dart';
import 'dart:math';
import '../widgets/glass_container.dart';
import '../components/history_graph.dart';
import '../services/history_service.dart';
import '../services/storage_service.dart';
import '../services/transaction_service.dart';
import '../services/category_icon_helper.dart';
import '../theme/app_colors.dart';
import 'package:intl/intl.dart';
import '../widgets/bottom_nav_bar.dart';
import 'allocator_screen.dart';
import 'detail_history_screen.dart';
import '../widgets/three_d_dropdown.dart';
import '../widgets/ditto_dropdown.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  String _mode = 'DAILY'; // DAILY, WEEKLY, MONTHLY
  DateTime _selectedDate = DateTime.now();
  int _selectedWeek = 0; // 0-indexed week of month
  int _forcedHighlightDay = -1;
  String? _filterCategory;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    
    // Default to current date and current week index
    final now = DateTime.now();
    _selectedDate = now;
    final firstOfMonth = DateTime(now.year, now.month, 1);
    // Correct week index logic: (day + firstDayOffset - 1) / 7
    _selectedWeek = ((now.day + firstOfMonth.weekday - 2) / 7).floor();
    
    // Highlight today by default (0-6 index, Mon-Sun)
    // DateTime.weekday is 1-7 (Mon-Sun). Convert to 0-6.
    _forcedHighlightDay = now.weekday - 1;
    
    _animationController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  DateTime _getMondayOfDate(DateTime date) {
    // Mon=1, Sun=7. We want Mon=1, so subtract (weekday - 1)
    return date.subtract(Duration(days: date.weekday - 1));
  }

  List<double> _getGraphValues() {
    final history = StorageService.historyList;
    final Map<int, double> dailyMap = {};
    final Map<int, double> weeklyMap = {};
    final Map<int, double> monthlyMap = {};

    for (var entry in history) {
      final p = entry.split('|');
      if (p.isEmpty) continue;

      double amount = 0.0;
      int hWeek = 0, hDay = 0, hMonth = 0, hYear = 0;
      String category = 'no choice';

      if (p.length == 7) {
        // ATSTMT|category|amount|week|day|month|year
        category = p[1];
        amount = double.tryParse(p[2]) ?? 0.0;
        hWeek = int.tryParse(p[3]) ?? 0;
        hDay = int.tryParse(p[4]) ?? 0;
        hMonth = int.tryParse(p[5]) ?? 0;
        hYear = int.tryParse(p[6]) ?? 0;
      } else if (p.length >= 9) {
        // EXP|timestamp|title|category|amount|week|day|month|year
        category = p[3];
        amount = double.tryParse(p[4]) ?? 0.0;
        hWeek = int.tryParse(p[5]) ?? 0;
        hDay = int.tryParse(p[6]) ?? 0;
        hMonth = int.tryParse(p[7]) ?? 0;
        hYear = int.tryParse(p[8]) ?? 0;
      } else continue;

      if (_filterCategory != null && category != _filterCategory) continue;

      if (hYear == _selectedDate.year) {
        // Monthly accumulator
        monthlyMap[hMonth] = (monthlyMap[hMonth] ?? 0.0) + amount;

        if (hMonth == _selectedDate.month - 1) {
          // Weekly accumulator
          weeklyMap[hWeek] = (weeklyMap[hWeek] ?? 0.0) + amount;

          if (hWeek == _selectedWeek) {
            // Daily accumulator
            final hDayMonIndex = hDay; // hDay is already 0-6 (Mon-Sun)
            dailyMap[hDayMonIndex] = (dailyMap[hDayMonIndex] ?? 0.0) + amount;
          }
        }
      }
    }

    if (_mode == 'DAILY') {
      return List.generate(7, (i) => dailyMap[i] ?? 0.0);
    } else if (_mode == 'WEEKLY') {
      final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final lastDay = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
      final totalWeeks = ((firstOfMonth.weekday - 1 + lastDay) / 7).ceil();
      return List.generate(totalWeeks, (i) => weeklyMap[i] ?? 0.0);
    } else {
      return List.generate(12, (i) => monthlyMap[i] ?? 0.0);
    }
  }

  List<String> _getGraphLabels() {
    if (_mode == 'DAILY') {
      final List<String> labels = [];
      // Sunday-Saturday or Monday-Sunday? Native seems to use custom labels.
      // updateDailyLabels in native uses Monday as start.
      final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      // Start of the selected week
      DateTime cal = DateTime(_selectedDate.year, _selectedDate.month, 1);
      // Move to Monday of the selected week
      int skipDays = (_selectedWeek * 7) - (firstOfMonth.weekday - 1);
      DateTime weekStart = firstOfMonth.add(Duration(days: skipDays));

      for (int i = 0; i < 7; i++) {
        DateTime d = weekStart.add(Duration(days: i));
        if (d.month == _selectedDate.month) {
          labels.add(DateFormat('dd/MM').format(d));
        } else {
          labels.add(""); 
        }
      }
      return labels;
    }
    if (_mode == 'WEEKLY') {
      final List<String> labels = [];
      final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final lastDay = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
      final totalWeeks = ((firstOfMonth.weekday - 1 + lastDay) / 7).ceil();

      for (int w = 0; w < totalWeeks; w++) {
        // Start of week: Monday or 1st
        int startDayOffset = (w * 7) - (firstOfMonth.weekday - 1);
        DateTime start = firstOfMonth.add(Duration(days: max(0, startDayOffset)));
        if (start.month != _selectedDate.month) start = firstOfMonth;

        // End of week: Sunday or last day
        int endDayOffset = (w * 7) + (7 - firstOfMonth.weekday);
        DateTime end = firstOfMonth.add(Duration(days: min(lastDay - 1, endDayOffset)));
        if (end.month != _selectedDate.month) {
           end = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
        }

        // Simplified range to avoid clash: "01-07"
        labels.add("${DateFormat('dd').format(start)}-${DateFormat('dd').format(end)}");
      }
      return labels;
    }
    return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  }

  int _getSelectedIndex() {
    if (_mode == 'DAILY') {
       if (_forcedHighlightDay != -1) return _forcedHighlightDay;
       final now = DateTime.now();
       if (_selectedDate.year == now.year && _selectedDate.month == now.month) {
          final firstOfMonth = DateTime(now.year, now.month, 1);
          final currentWeek = ((now.day + firstOfMonth.weekday - 2) / 7).floor();
          if (currentWeek == _selectedWeek) return now.weekday - 1;
       }
       return -1;
    }
    if (_mode == 'WEEKLY') {
       final now = DateTime.now();
       if (_selectedDate.year == now.year && _selectedDate.month == now.month) {
          final firstOfMonth = DateTime(now.year, now.month, 1);
          return ((now.day + firstOfMonth.weekday - 2) / 7).floor();
       }
       return -1;
    }
    final now = DateTime.now();
    if (_selectedDate.year == now.year) return now.month - 1;
    return -1;
  }

  Widget _buildGraphSection() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Opacity(
          opacity: _animationController.value,
          child: Transform.scale(
            scale: 0.95 + (0.05 * _animationController.value),
            child: child,
          ),
        );
      },
      child: HistoryGraph(
        key: ValueKey('${_mode}_${_selectedDate.year}_${_selectedDate.month}'),
        mode: _mode,
        values: _getGraphValues(),
        labels: _getGraphLabels(),
        selectedIndex: _getSelectedIndex(),
        onBarTap: (index) {
          if (_mode == 'MONTHLY') {
            setState(() {
              _mode = 'WEEKLY';
              _selectedDate = DateTime(_selectedDate.year, index + 1, 1);
              // Match native: default to week 0, or current week if it's current month
              final now = DateTime.now();
              if (now.year == _selectedDate.year && now.month == _selectedDate.month) {
                final firstOfMonth = DateTime(now.year, now.month, 1);
                _selectedWeek = ((now.day + firstOfMonth.weekday - 2) / 7).floor();
              } else {
                _selectedWeek = 0;
              }
              _forcedHighlightDay = -1;
              _animationController.forward(from: 0.0);
            });
          } else if (_mode == 'WEEKLY') {
            setState(() {
              _mode = 'DAILY';
              _selectedWeek = index;
              _forcedHighlightDay = -1;
              _animationController.forward(from: 0.0);
            });
          } else {
            // DAILY -> Breakdown
            final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
            int skipDays = (_selectedWeek * 7) - (firstOfMonth.weekday - 1);
            DateTime weekStart = firstOfMonth.add(Duration(days: skipDays));
            DateTime actualDate = weekStart.add(Duration(days: index));
            
            // Native ignores clicks on empty labels (days belonging to other months)
            if (actualDate.month != _selectedDate.month) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetailHistoryScreen(
                  mode: _mode,
                  year: actualDate.year,
                  month: actualDate.month - 1,
                  week: _selectedWeek,
                  day: index, // Send 0-6 index for matching
                ),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 30),
                _buildHeader(),
                _buildTopControls(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _buildGraphSection(),
                        const SizedBox(height: 15),
                        _buildGraphTitle(),
                        const SizedBox(height: 140), // Space for nav bar
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassBottomNavBar(
                selectedIndex: 2,
                scrollPosition: 2.0,
                onTabSelected: (index) {
                  if (index == 0) {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AllocatorScreen()));
                  } else if (index == 1) {
                    Navigator.pop(context); // Home
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: const [
          Expanded(
            child: Center(
              child: Text(
                'History',
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 2), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Rect _getWidgetRect(BuildContext ctx) {
    final RenderBox box = ctx.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  Widget _buildTopControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Builder(builder: (ctx) => ThreeDDropdown(
            text: _mode[0] + _mode.substring(1).toLowerCase(), 
            width: 104, 
            onTap: () => _showModeMenu(ctx),
          )),
          const SizedBox(width: 12),
          Builder(builder: (ctx) => ThreeDDropdown(
            text: _getShortDateLabel(), 
            width: 135, 
            onTap: () => _showDatePicker(ctx),
          )),
          const SizedBox(width: 12),
          Builder(builder: (ctx) => ThreeDDropdown(
            text: _filterCategory ?? 'Overall', 
            width: 100, 
            onTap: () => _showFilterDialog(ctx),
          )),
        ],
      ),
    );
  }


  String _getShortDateLabel() {
    if (_mode == 'DAILY') {
      final now = DateTime.now();
      // If currently looking at "Today" (current year, month, day), show full date
      if (_selectedDate.year == now.year &&
          _selectedDate.month == now.month &&
          (_forcedHighlightDay == -1 || _forcedHighlightDay == now.weekday - 1)) {
        return DateFormat('MMMM d, yyyy').format(now);
      }
      // If we've picked a specific day via DatePicker or BarTap
      if (_forcedHighlightDay != -1) {
        final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
        int skipDays = (_selectedWeek * 7) - (firstOfMonth.weekday - 1);
        DateTime weekStart = firstOfMonth.add(Duration(days: skipDays));
        DateTime actual = weekStart.add(Duration(days: _forcedHighlightDay));
        // If it's still today's day but forced, show full date
        if (actual.year == now.year && actual.month == now.month && actual.day == now.day) {
           return DateFormat('MMMM d, yyyy').format(actual);
        }
        return DateFormat('MMMM d, yyyy').format(actual);
      }
      
      // Default for Daily: Month Year (if not looking at today)
      return DateFormat('MMMM yyyy').format(_selectedDate);
    } else if (_mode == 'WEEKLY') {
      return 'Week ${_selectedWeek + 1}';
    } else {
      return _selectedDate.year.toString();
    }
  }

  Widget _buildGraphTitle() {
    String title = '';
    if (_mode == 'DAILY') title = 'Daily Spending';
    else if (_mode == 'WEEKLY') title = 'Weekly Spending';
    else title = 'Monthly Spending';

    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 2), blurRadius: 6),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext ctx) {
    final categories = ['Overall', ...StorageService.categories];
    DittoDropdown.show(
      context: context,
      anchorRect: _getWidgetRect(ctx),
      items: categories,
      onSelected: (cat) {
        setState(() => _filterCategory = cat == 'Overall' ? null : cat);
      },
    );
  }

  void _showModeMenu(BuildContext ctx) {
    final modes = ['Daily', 'Weekly', 'Monthly'];
    DittoDropdown.show(
      context: context,
      anchorRect: _getWidgetRect(ctx),
      items: modes,
      onSelected: (m) {
        setState(() {
          _mode = m.toUpperCase();
          _forcedHighlightDay = -1;
          if (_mode == 'WEEKLY') {
             final now = DateTime.now();
             if (now.year == _selectedDate.year && now.month == _selectedDate.month) {
                final firstOfMonth = DateTime(now.year, now.month, 1);
                _selectedWeek = ((now.day + firstOfMonth.weekday - 2) / 7).floor();
             } else {
                _selectedWeek = 0;
             }
          }
          _animationController.forward(from: 0.0);
        });
      },
    );
  }

  void _showDatePicker(BuildContext ctx) async {
    if (_mode == 'MONTHLY') {
      final int currentYear = DateTime.now().year;
      final List<String> years = [];
      for (int i = -2; i <= 2; i++) {
        years.add((currentYear + i).toString());
      }

      DittoDropdown.show(
        context: context,
        anchorRect: _getWidgetRect(ctx),
        items: years,
        onSelected: (yearStr) {
          final year = int.tryParse(yearStr);
          if (year != null) {
            setState(() {
              _selectedDate = DateTime(year, _selectedDate.month, _selectedDate.day);
            });
          }
        },
      );
    } else {
      // Standard Date Picker for Daily/Weekly
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2101),
        builder: (context, child) {
          return Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppColors.neonBlue,
                onPrimary: Colors.white,
                surface: Color(0xFF0F174A),
                onSurface: Colors.white,
              ),
              dialogBackgroundColor: const Color(0xFF0F174A),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        setState(() {
          _selectedDate = picked;
          final firstOfMonth = DateTime(picked.year, picked.month, 1);
          _selectedWeek = ((picked.day + firstOfMonth.weekday - 2) / 7).floor();
          
          if (_mode == 'DAILY') {
            _forcedHighlightDay = picked.weekday - 1;
          } else {
            _forcedHighlightDay = -1;
          }
        });
      }
    }
  }


}
