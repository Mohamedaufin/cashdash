import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import 'help_screen.dart';
import 'balance_setup_screen.dart';
import 'money_schedule_screen.dart';
import 'notification_screen.dart'; // We will create this

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool _hasUnreadReply = false;

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      bool unread = false;
      for (var doc in snapshot.docs) {
        final reply = doc.data()['reply']?.toString().trim();
        if (reply != null && reply.isNotEmpty && reply != 'Waiting for reply...') {
          unread = true;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _hasUnreadReply = unread;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 30.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // Top Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Arrow Button (btnCloseMenu)
                    _circularGlassBtn(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    
                    // Notification Icon Container
                    _notificationBtn(context),
                  ],
                ),
                
                const SizedBox(height: 50),
                
                // Balance Bar Button
                _glass3dButton(
                  'Balance bar',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const BalanceSetupScreen()));
                  },
                ),
                
                const SizedBox(height: 30),
                
                // Update Money Schedule Button
                _glass3dButton(
                  'Update money schedule',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MoneyScheduleScreen()));
                  },
                ),
                
                const SizedBox(height: 30),
                
                // Help Button
                _glass3dButton(
                  'Help',
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen()));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circularGlassBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 55,
        height: 55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: Colors.white, size: 28),
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
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.1),
              Colors.white.withOpacity(0.03),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 2,
              right: 2,
              height: 35,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.12),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(color: Colors.black26, offset: Offset(0, 2), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationBtn(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _hasUnreadReply = false;
        });
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const NotificationScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Container(
        width: 55,
        height: 55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_outlined, color: Colors.white, size: 28),
            if (_hasUnreadReply)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF001133), width: 1.5), // Match background color roughly
                    boxShadow: [
                      BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 4, spreadRadius: 1),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
