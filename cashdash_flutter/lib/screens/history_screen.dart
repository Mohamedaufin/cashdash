import 'package:flutter/material.dart';
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
  String? _filterCategory;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
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
      if (p.length < 5) continue;

      final category = p[3];
      final amount = double.tryParse(p[4]) ?? 0.0;
      final timestamp = int.tryParse(p[1]) ?? 0;

      if (_filterCategory != null && category != _filterCategory) continue;

      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (date.year != _selectedDate.year) continue;

      // Month Index
      final hMonth = date.month - 1;
      monthlyMap[hMonth] = (monthlyMap[hMonth] ?? 0.0) + amount;

      if (hMonth == _selectedDate.month - 1) {
        // Week Index
        final firstOfMonth = DateTime(date.year, date.month, 1);
        final hWeek = ((date.day + firstOfMonth.weekday - 2) / 7).floor();
        weeklyMap[hWeek] = (weeklyMap[hWeek] ?? 0.0) + amount;

        // Day Index (Mon=0)
        final mondayOfSelected = _getMondayOfDate(_selectedDate);
        final sundayOfSelected = mondayOfSelected.add(const Duration(days: 6));
        
        // We only care about the day index if it falls within the visible week of _selectedDate
        if (date.isAfter(mondayOfSelected.subtract(const Duration(seconds: 1))) && 
            date.isBefore(sundayOfSelected.add(const Duration(seconds: 1)))) {
           final hDay = date.weekday - 1;
           dailyMap[hDay] = (dailyMap[hDay] ?? 0.0) + amount;
        }
      }
    }

    if (_mode == 'DAILY') {
      return List.generate(7, (i) => dailyMap[i] ?? 0.0);
    } else if (_mode == 'WEEKLY') {
      final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final totalWeeks = ((firstOfMonth.weekday - 1 + DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day) / 7).ceil();
      return List.generate(totalWeeks, (i) => weeklyMap[i] ?? 0.0);
    } else {
      return List.generate(12, (i) => monthlyMap[i] ?? 0.0);
    }
  }

  List<String> _getGraphLabels() {
    if (_mode == 'DAILY') {
      final List<String> dates = [];
      final monday = _getMondayOfDate(_selectedDate);
      for (int i = 0; i < 7; i++) {
        final d = monday.add(Duration(days: i));
        if (d.month == _selectedDate.month) {
          dates.add(DateFormat('dd/MM').format(d));
        } else {
          dates.add(""); // Day belongs to another month
        }
      }
      return dates;
    }
    if (_mode == 'WEEKLY') {
      final List<String> ranges = [];
      final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final totalWeeks = ((firstOfMonth.weekday - 1 + DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day) / 7).ceil();
      
      for (int w = 0; w < totalWeeks; w++) {
        // Start of week: Monday or 1st
        DateTime start = firstOfMonth.add(Duration(days: w * 7 - (firstOfMonth.weekday - 1)));
        if (start.month != firstOfMonth.month) start = firstOfMonth;
        
        // End of week: Sunday or last day
        DateTime end = start.add(Duration(days: 6 - (start == firstOfMonth ? 0 : 0))); // Simple approx
        // Refine end to match native: Sunday of that week or last day of month
        DateTime sunday = firstOfMonth.add(Duration(days: w * 7 + (7 - firstOfMonth.weekday)));
        if (sunday.month != firstOfMonth.month) sunday = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0);
        
        ranges.add("${DateFormat('dd/MM').format(start)}-${DateFormat('dd/MM').format(sunday)}");
      }
      return ranges;
    }
    return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  }

  int _getSelectedIndex() {
    if (_mode == 'DAILY') return _selectedDate.weekday - 1; // Mon=0, Sun=6
    if (_mode == 'WEEKLY') {
       final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
       return ((_selectedDate.day + firstOfMonth.weekday - 2) / 7).floor();
    }
    return _selectedDate.month - 1;
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
              _animationController.forward(from: 0.0);
            });
          } else if (_mode == 'WEEKLY') {
            setState(() {
              _mode = 'DAILY';
              // Find the start of the week for the selected month
              final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
              final startOfWeek = firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));
              _selectedDate = startOfWeek.add(Duration(days: index * 7));
              // Ensure we stay within the month if native does that
              if (_selectedDate.month != firstOfMonth.month && index == 0) {
                 _selectedDate = firstOfMonth;
              }
              _animationController.forward(from: 0.0);
            });
          } else {
            // DAILY -> Breakdown
            final monday = _getMondayOfDate(_selectedDate);
            final actualDate = monday.add(Duration(days: index));
            
            final firstOfMonth = DateTime(actualDate.year, actualDate.month, 1);
            final day = actualDate.day - 1;
            final week = ((actualDate.day + firstOfMonth.weekday - 2) / 7).floor();
            final month = actualDate.month - 1;
            final year = actualDate.year;
            
            setState(() => _selectedDate = actualDate);

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetailHistoryScreen(
                  mode: _mode,
                  week: week,
                  day: day,
                  month: month,
                  year: year,
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
                const SizedBox(height: 50),
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
      return DateFormat('dd/MM/yyyy').format(_selectedDate);
    } else if (_mode == 'WEEKLY') {
      return 'Week ${((_selectedDate.day - 1) / 7).floor() + 1}';
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
      if (picked != null && picked != _selectedDate) {
        setState(() => _selectedDate = picked);
      }
    }
  }


}
