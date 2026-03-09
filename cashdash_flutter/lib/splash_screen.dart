import 'package:flutter/material.dart';
import 'dart:async';
import 'theme/app_colors.dart';
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'screens/balance_setup_screen.dart';
import 'services/firebase_service.dart';
import 'services/storage_service.dart';
import 'widgets/glass_container.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    // DITTO NATIVE ROUTING
    final bool isFirst = StorageService.isFirstLaunch;
    final int initialBal = StorageService.initialBalance;
    final user = FirebaseService.currentUser;

    if (isFirst || user == null) {
      // Immediate jump to Auth
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      });
      return;
    } else if (initialBal != -1) {
      // Immediate jump to Scanner
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen(startTab: 3)),
        );
      });
      return;
    }

    // Otherwise, show the Welcome Splash with 1500ms delay (matching native postDelayed)
    _controller.forward();

    // Setup Admin Listener
    FirebaseService.setupAdminListener(() {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen(adminNotice: "Admin has deleted your account due to privacy concerns.")),
          (route) => false,
        );
      }
    });

    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showWelcome = StorageService.initialBalance == 0 && FirebaseService.currentUser != null;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Center(
                  child: showWelcome 
                  ? Hero(
                        tag: 'greeting_text_transition',
                        child: Material(
                          color: Colors.transparent,
                          child: Text(
                            'Welcome ${StorageService.userName}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                              shadows: [Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 4), blurRadius: 10)],
                            ),
                          ),
                        ),
                      )
                  : Image.asset(
                    'assets/icons/bg_splash_hero.png',
                    width: MediaQuery.of(context).size.width * 0.85,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet, size: 80, color: Colors.amber),
                        SizedBox(height: 24),
                        Text(
                          'CashDash',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                            shadows: [Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 4), blurRadius: 10)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
