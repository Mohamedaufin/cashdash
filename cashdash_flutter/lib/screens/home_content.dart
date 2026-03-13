import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../theme/app_colors.dart';
import '../services/storage_service.dart';
import '../components/gradient_circular_progress.dart';
import '../widgets/glass_container.dart';
import 'scanner_screen.dart';
import 'rigor_screen.dart';
import 'profile_screen.dart';
import '../widgets/glass_menu_icon.dart';
import 'menu_screen.dart';

class HomeContent extends StatefulWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  
  const HomeContent({super.key, required this.scaffoldKey});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  void _loadBalance() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bal = StorageService.walletBalance;
    final initial = StorageService.initialBalance;
    final displayInitial = (initial == 0 && bal == 0) ? 0 : initial.clamp(1, double.infinity).toInt();
    
    final nextMoneyStr = StorageService.nextMoneyDate != null 
        ? 'This money is tentatively till ${StorageService.nextMoneyDate}' 
        : 'Next money: schedule not set';

    return VisibilityDetector(
      key: const Key('home-content'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.5) _loadBalance();
      },
      child: SingleChildScrollView( 
        child: Column(
          children: [
            const SizedBox(height: 54), 
            _buildTopBar(context),
            
            const SizedBox(height: 15), 
            Transform.translate(
              offset: const Offset(0, 15), // Move text ~1 inch down
              child: Text(
                nextMoneyStr,
                style: const TextStyle(
                  color: Color(0xFFB0C8FF),
                  fontSize: 18,
                  shadows: [Shadow(color: Color(0xFF1A2D8A), offset: Offset(0, 2), blurRadius: 8)],
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            _buildWalletCircle(context, bal, displayInitial),
            
            const SizedBox(height: 28), 
            _buildActionCards(context),
            
            const SizedBox(height: 160), 
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center, // Already center, but ensuring
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const MenuScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(top: 2), // Visual nudge for alignment
                    child: GlassMenuIcon(size: 30),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Hero(
                    tag: 'greeting_text_transition',
                    child: Material(
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4), // Aligned with icon center
                        child: Text(
                          'Hello ${StorageService.userName ?? "User"},',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 2), blurRadius: 6)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
            child: Image.asset(
              'assets/icons/ic_profile.png',
              width: 44,
              height: 44,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCircle(BuildContext context, int bal, int initial) {
    final double screenW = MediaQuery.of(context).size.width;
    final double circleSize = screenW * 0.92; 
    final double glowSize = circleSize * 1.1;
    final double progress = initial > 0 ? (bal / initial) * 100 : 0;

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: circleSize,
          height: circleSize,
          child: GradientCircularProgress(
            progress: progress, 
            animate: true,
            strokeWidth: 45.0, 
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Text(
              '₹$bal/$initial',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Wallet balance',
              style: TextStyle(
                color: Color(0xFFB0C4FF),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCards(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionCard(
            'Scanner', 
            'assets/icons/ic_scanner.png', 
            86, 60, 
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()))
          ),
          _buildActionCard(
            'Rigor Tracker', 
            'assets/icons/ic_rigor_tracker.png', 
            80, 58,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RigorScreen()))
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(String title, String assetPath, double iconW, double iconH, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ThreeDCard(
        width: 120,
        height: 115,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center, // Centering icons and text
            children: [
              Image.asset(assetPath, width: iconW, height: iconH, fit: BoxFit.contain),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center, // Ensure multi-line if any is centered
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Color(0xFF000C40), offset: Offset(0, 2), blurRadius: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
