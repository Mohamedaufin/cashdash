import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/firebase_service.dart';
import '../services/storage_service.dart';
import 'auth_screen.dart';

/// Mirrors activity_profile.xml — scrollable column with glass-3D styled buttons.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: StorageService.userName);
    _phoneController = TextEditingController(text: StorageService.userPhone);
    _emailController = TextEditingController(text: FirebaseService.currentUser?.email ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Glass input field matching bg_glass_input drawable
  Widget _glassInput(TextEditingController ctrl, String hint,
      {TextInputType keyboard = TextInputType.text, bool enabled = true}) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Layer 1: Deep Background (bg_glass_input.xml)
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A2D8A), Color(0xFF101B54)],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Layer 2: Frosted overlay
          color: Colors.white.withOpacity(0.12),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
        ),
        child: TextField(
          controller: ctrl,
          enabled: enabled,
          keyboardType: keyboard,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9EB2FF)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  // Glass 3D button — matches bg_glass_3d drawable
  Widget _glass3dButton(String label, VoidCallback onTap, {Color? textColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 65,
        margin: const EdgeInsets.only(bottom: 25),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          // Layer 1: Base Glass
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
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Stack(
          children: [
            // Layer 2: Top Gloss Highlight
            Positioned(
              top: 0,
              left: 2,
              right: 2,
              height: 32,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
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
                style: TextStyle(
                  color: textColor ?? Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: const [
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

  // Red glass 3D danger button — matches bg_glass_3d_red
  Widget _redGlass3dButton(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 65,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // Layer 1: Red Base
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6B1515), Color(0xFF300A0A)],
            ),
            border: Border.all(color: const Color(0x77FF3333), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.redAccent.withOpacity(0.25), blurRadius: 12),
            ],
          ),
          child: Stack(
            children: [
              // Layer 2: Red Gloss Highlight (bg_glass_3d_red.xml)
              Positioned(
                top: 0,
                left: 2,
                right: 2,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0x30FFAAAA).withOpacity(0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgEndColor, // Fallback during transitions
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.mainBackgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Name field
                      _glassInput(_nameController, 'Name'),
                      // Phone field
                      _glassInput(_phoneController, 'Phone Number',
                          keyboard: TextInputType.phone),
                      // Email (read-only display)
                      _glassInput(_emailController, 'Email',
                          keyboard: TextInputType.emailAddress, enabled: false),
      
                      // Save
                      _glass3dButton('Save', _saveProfile),
                      const SizedBox(height: 10),
      
                      // Change Password
                      _glass3dButton('Change Password', _showChangePasswordDialog),
                      const SizedBox(height: 35),
      
                      // Logout + Delete row
                      Row(
                        children: [
                          _redGlass3dButton('Logout', _handleLogout),
                          const SizedBox(width: 16),
                          _redGlass3dButton('Delete Account', _handleDeleteAccount),
                        ],
                      ),
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
                'Edit Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: AppColors.neonBlue, blurRadius: 10)],
                ),
              ),
            ),
          ),
          const SizedBox(width: 40), // Balance the back button
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    StorageService.userName = _nameController.text.trim();
    StorageService.userPhone = _phoneController.text.trim();
    await FirebaseService.pushAllDataToCloud();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved!')));
    }
  }

  void _showChangePasswordDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change Password', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'New Password', hintStyle: TextStyle(color: Colors.white24)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (ctrl.text.length < 6) return;
              await FirebaseService.currentUser?.updatePassword(ctrl.text);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Update', style: TextStyle(color: Color(0xFF8BF7E6))),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    await FirebaseService.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
    }
  }

  void _handleDeleteAccount() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Account?',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text(
            'This will permanently delete all your data. This cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await FirebaseService.currentUser?.delete();
              await StorageService.clearAll();
              if (mounted) {
                Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
