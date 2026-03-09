import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/storage_service.dart';
import '../services/firebase_service.dart';
import '../widgets/glass_container.dart';
import '../splash_screen.dart';
import '../theme/app_styles.dart';

class AuthScreen extends StatefulWidget {
  final String? adminNotice;
  const AuthScreen({super.key, this.adminNotice});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.adminNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAdminDeletionDialog();
      });
    }
  }

  void _showAdminDeletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Security Notice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Admin has deleted your account due to privacy concerns. Please register a new account.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood', style: TextStyle(color: Color(0xFF8BF7E6))),
          ),
        ],
      ),
    );
  }

  bool _isSelectionVisible = true;
  bool _isLoginFlow = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.mainBackgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 100),
                const Text(
                  'CashDash',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Color(0xFF3A6AFF), offset: Offset(0, 2), blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage your wealth wisely',
                  style: TextStyle(
                    color: Color(0xFF9EB2FF),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 50),
                
                if (_isSelectionVisible) ...[
                  _glass3dButton('Login', () {
                    setState(() {
                      _isLoginFlow = true;
                      _isSelectionVisible = false;
                      _statusMessage = '';
                    });
                  }),
                  const SizedBox(height: 16),
                  _glass3dButton('Register', () {
                    setState(() {
                      _isLoginFlow = false;
                      _isSelectionVisible = false;
                      _statusMessage = '';
                    });
                  }),
                ] else ...[
                  if (!_isLoginFlow) ...[
                    _glassInput(_nameController, 'Name'),
                    const SizedBox(height: 20),
                    _glassInput(_phoneController, 'Phone Number', keyboard: TextInputType.phone),
                    const SizedBox(height: 20),
                  ],
                  _glassInput(_emailController, 'Email', keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 20),
                  _glassInput(_passwordController, 'Password', isPass: true),
                  const SizedBox(height: 35),
                  
                  _glass3dButton(_isLoginFlow ? 'Login' : 'Register', () => _handleAuth(isLogin: _isLoginFlow)),
                  
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isSelectionVisible = true;
                        _statusMessage = '';
                      });
                    },
                    child: const Text(
                      'Back',
                      style: TextStyle(color: Color(0xFF9EB2FF), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                
                if (_isLoginFlow && !_isSelectionVisible) ...[
                  const SizedBox(height: 25),
                  GestureDetector(
                    onTap: _handleForgotPassword,
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(color: Color(0xFFB0C8FF), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator(color: AppColors.neonCyan)
                else
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusMessage.contains('sent') ? AppColors.neonCyan : AppColors.errorRed,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassInput(TextEditingController ctrl, String hint, {bool isPass = false, TextInputType keyboard = TextInputType.text}) {
    // Map hints to Flutter AutofillHints
    Iterable<String>? autofill;
    if (isPass) {
      autofill = [AutofillHints.password];
    } else if (keyboard == TextInputType.emailAddress) {
      autofill = [AutofillHints.email];
    } else if (keyboard == TextInputType.phone) {
      autofill = [AutofillHints.telephoneNumber];
    } else if (hint.toLowerCase().contains('name')) {
      autofill = [AutofillHints.name];
    }

    return Container(
      height: 60,
      decoration: AppStyles.glassInputDecoration,
      child: Stack(
        children: [
          AppStyles.glassInputOverlay,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: ctrl,
              obscureText: isPass,
              keyboardType: keyboard,
              autofillHints: autofill,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF9EB2FF), fontSize: 16),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glass3dButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 65,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          // Layer 1: Base Glass (bg_glass_3d.xml)
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.15),
              Colors.white.withOpacity(0.05),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
        ),
        child: Stack(
          children: [
            // Layer 2: Top Gloss Highlight
            Positioned(
              top: 0,
              left: 2,
              right: 2,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.15),
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
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAuth({required bool isLogin}) async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _statusMessage = 'Please fill in email and password');
      return;
    }
    
    if (!isLogin && (name.isEmpty || phone.isEmpty)) {
      setState(() => _statusMessage = 'Please fill in all fields');
      return;
    }

    if (pass.length < 6) {
      setState(() => _statusMessage = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      // CLEAR STORAGE to ensure data isolation between different user sessions
      await StorageService.clearAll();

      if (isLogin) {
        await FirebaseService.signIn(email, pass);
        // Mirrors pullDataFromCloud in native
        final profileExists = await FirebaseService.pullDataFromCloud();
        if (!profileExists) {
          // Admin deleted profile document
          await FirebaseService.signOut();
          await StorageService.clearAll();
          setState(() {
            _isLoading = false;
            _statusMessage = '';
          });
          _showAdminDeletionDialog();
          return;
        }
      } else {
        try {
          await FirebaseService.signUp(email, pass);
        } catch (e) {
          // Check if it's an admin-deleted account allowing re-registration
          // Mirrors the complex fallback in EntryActivity.kt
          await FirebaseService.signIn(email, pass);
          final profileExists = await FirebaseService.pullDataFromCloud();
          if (profileExists) {
            throw 'Account already exists. Please use Login.';
          }
          // Profile doesn't exist -> Admin deleted. Proceed with registration flow.
        }
      }

      // Success -> Save Prefs
      StorageService.userName = name;
      StorageService.userPhone = phone;
      StorageService.userPassword = pass;
      StorageService.isFirstLaunch = false;
      
      if (!isLogin) {
        // PUSH empty data if registering
        await FirebaseService.pushAllDataToCloud();
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SplashScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _statusMessage = 'Enter email to reset password');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      await FirebaseService.sendPasswordReset(email);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Reset link sent to $email';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Failed to send reset link';
        });
      }
    }
  }
}
