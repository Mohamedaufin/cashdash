import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/firebase_service.dart';
import '../services/storage_service.dart';
import 'auth_screen.dart';
import '../components/glass_input.dart';
import '../components/glass_button.dart';
import '../components/transaction_dialog.dart';

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

  // REMOVED: Local glass helpers (now using global components)

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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: GlassInput(controller: _nameController, hintText: 'Name'),
                      ),
                      // Phone field
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: GlassInput(
                          controller: _phoneController,
                          hintText: 'Phone Number',
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      // Email (read-only display)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: GlassInput(
                          controller: _emailController,
                          hintText: 'Email',
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
      
                      // Save
                      Padding(
                        padding: const EdgeInsets.only(bottom: 25),
                        child: GlassButton(label: 'Save Profile', onTap: _saveProfile),
                      ),
      
                      // Change Password
                      Padding(
                        padding: const EdgeInsets.only(bottom: 25),
                        child: GlassButton(label: 'Change Password', onTap: _showChangePasswordDialog),
                      ),
                      const SizedBox(height: 35),
      
                      // Logout + Delete row
                      Row(
                        children: [
                          Expanded(
                            child: GlassButton(
                              label: 'Logout',
                              color: Colors.redAccent,
                              onTap: _handleLogout,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GlassButton(
                              label: 'Delete Account',
                              color: Colors.redAccent,
                              onTap: _handleDeleteAccount,
                            ),
                          ),
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
          .showSnackBar(const SnackBar(content: Text('Profile updated')));
      // Native parity: navigate back to main activity
      Navigator.pop(context);
    }
  }

  void _showChangePasswordDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => TransactionDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Change Password',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              GlassInput(
                controller: ctrl,
                hintText: 'New Password',
                obscureText: true,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Cancel',
                      isSecondary: true,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassButton(
                      label: 'Update',
                      isSecondary: true,
                      onTap: () async {
                        if (ctrl.text.length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password too short')),
                          );
                          return;
                        }
                        await FirebaseService.currentUser?.updatePassword(ctrl.text);
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TransactionDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout, color: Colors.blueAccent, size: 60),
              const SizedBox(height: 20),
              const Text(
                'Logout?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to logout? All your data is safely synced to the cloud.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Cancel',
                      isSecondary: true,
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassButton(
                      label: 'Logout',
                      color: Colors.redAccent,
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await FirebaseService.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
      }
    }
  }

  void _handleDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => TransactionDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.gpp_maybe_rounded, color: Colors.redAccent, size: 72),
              const SizedBox(height: 20),
              const Text(
                'Delete Account?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'WARNING: This is permanent! All your expense history, budget categories, and wallet settings will be deleted from the cloud and this device. Are you sure?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Cancel',
                      isSecondary: true,
                      onTap: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassButton(
                      label: 'DELETE',
                      color: Colors.redAccent,
                      onTap: () async {
                        try {
                          // 1. Clear local storage first
                          await StorageService.clearAll();
                          // 2. Delete Firebase Auth user
                          await FirebaseService.currentUser?.delete();
                          
                          if (mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const AuthScreen()),
                              (_) => false,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Error deleting account. Please login again to verify identity.')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
