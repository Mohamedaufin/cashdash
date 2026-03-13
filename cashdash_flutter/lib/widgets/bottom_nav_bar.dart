import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GlassBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final double scrollPosition;
  final Function(int) onTabSelected;

  const GlassBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.scrollPosition,
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
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.navGlossStart, AppColors.navGlossEnd],
              ),
            ),
          ),
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
    // Distance from target page (1.0 for home)
    final double distance = (scrollPosition - 1.0).abs().clamp(0.0, 1.0);
    
    // Interpolate values
    final double scale = 1.0 - (0.5 * distance); // 1.0 to 0.5
    final double alpha = 1.0 - (0.4 * distance); // 1.0 to 0.6
    final Color color = Color.lerp(Colors.white, const Color(0xFFD0E0FF), distance)!;

    return InkWell(
      onTap: () => onTabSelected(1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: alpha,
              child: Image.asset(
                'assets/icons/ic_home.png',
                width: 166,
                height: 84,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(0, -(1.0 - scale) * 42), // iconHeightPx / 2
            child: Text(
              'Home',
              style: TextStyle(
                color: color.withOpacity(alpha),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Color.lerp(const Color(0xFF3A6AFF), const Color(0xFF000C40), distance)!, 
                    offset: const Offset(0, 2), 
                    blurRadius: 4.0 + (2.0 * (1.0 - distance))
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, String label, String assetPath, double iconW, double iconH, {required Color shadowColor}) {
    // Distance from target page (0.0 or 2.0)
    final double distance = (scrollPosition - index.toDouble()).abs().clamp(0.0, 1.0);
    
    // Interpolate values
    final double scale = 1.0 - (0.5 * distance); // 1.0 to 0.5
    final double alpha = 1.0 - (0.4 * distance); // 1.0 to 0.6
    final Color color = Color.lerp(Colors.white, const Color(0xFFD0E0FF), distance)!;

    return InkWell(
      onTap: () => onTabSelected(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: alpha,
              child: Image.asset(
                assetPath, 
                width: iconW * 2.1, 
                height: iconH * 2.1, 
                fit: BoxFit.contain,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(0, -(1.0 - scale) * (iconH * 2.1 / 2)),
            child: Text(
              label,
              style: TextStyle(
                color: color.withOpacity(alpha),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Color.lerp(const Color(0xFF3A6AFF), shadowColor, distance)!, 
                    offset: const Offset(0, 2), 
                    blurRadius: 4.0 + (2.0 * (1.0 - distance))
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
