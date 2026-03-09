import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GlassBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabSelected;

  const GlassBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 135, // Native match: android:layout_height="135dp"
      width: double.infinity,
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(color: Colors.black45, blurRadius: 32, offset: Offset(0, -10)),
        ],
      ),
      child: Stack(
        children: [
          // 3D background matching bg_3d_bottom_nav.xml
          // Layer 1: Glossy transition
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.navGlossStart, AppColors.navGlossEnd],
              ),
            ),
          ),
          // Layer 2: Main Body (shifted 2dp down)
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.navBodyStart, AppColors.navBodyEnd],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  context, 0, 'Allocator', 'assets/icons/ic_allocator.png', 40, 40,
                  shadowColor: const Color(0xFF000C40),
                ),
              ),
              Expanded(
                child: _buildHomeNavItem(context),
              ),
              Expanded(
                child: _buildNavItem(
                  context, 2, 'History', 'assets/icons/ic_history.png', 42, 42,
                  shadowColor: const Color(0xFF000C40),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHomeNavItem(BuildContext context) {
    final isSelected = selectedIndex == 1;
    return InkWell(
      onTap: () => onTabSelected(1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // THE DITTO HOME ICON (166x84 in native XML, scale down if not selected)
              Image.asset(
                'assets/icons/ic_home.png',
                width: isSelected ? 166 : 70, // scaling down unselected
                height: isSelected ? 84 : 35, // scaling down unselected
                fit: BoxFit.contain,
                color: isSelected ? null : Colors.white70, // Gray out unselected
              ),
            ],
          ),
          SizedBox(height: isSelected ? 3 : 8),
          Text(
            'Home',
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFFD0E0FF),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              shadows: isSelected 
                ? [const Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 2), blurRadius: 6)]
                : [const Shadow(color: Color(0xFF000C40), offset: Offset(0, 2), blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, String label, String assetPath, double iconW, double iconH, {required Color shadowColor}) {
    final isSelected = selectedIndex == index;
    final textColor = isSelected ? Colors.white : const Color(0xFFD0E0FF);

    return InkWell(
      onTap: () => onTabSelected(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                assetPath, 
                width: isSelected ? iconW * 2.1 : iconW, // Scaled massively to match Home size visually
                height: isSelected ? iconH * 2.1 : iconH, 
                fit: BoxFit.contain,
                color: isSelected ? null : Colors.white70,
              ),
            ],
          ),
          SizedBox(height: isSelected ? 4 : 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: isSelected ? const Color(0xFF3A6AFF) : shadowColor, 
                  offset: const Offset(0, 2), 
                  blurRadius: isSelected ? 6 : 4
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
