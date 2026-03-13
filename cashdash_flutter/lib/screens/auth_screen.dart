import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/storage_service.dart';
import '../services/firebase_service.dart';
import '../widgets/glass_container.dart';
import '../splash_screen.dart';
import '../theme/app_styles.dart';
import '../components/transaction_dialog.dart';
import '../components/glass_input.dart';
import '../components/glass_button.dart';

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
      builder: (ctx) => TransactionDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, color: Colors.orangeAccent, size: 64),
              const SizedBox(height: 20),
              const Text(
                'Security Notice',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Admin has deleted your account due to privacy concerns. Please register a new account.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 32),
              GlassButton(
                label: 'Understood',
                isSecondary: true,
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAuthFeedback({required String title, required String message, bool isError = true}) {
    showDialog(
      context: context,
      builder: (ctx) => TransactionDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.redAccent : AppColors.neonCyan,
                size: 64,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 32),
              GlassButton(
                label: 'Close',
                isSecondary: true,
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
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
                  GlassButton(
                    label: 'Login',
                    onTap: () {
                      setState(() {
                        _isLoginFlow = true;
                        _isSelectionVisible = false;
                        _statusMessage = '';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  GlassButton(
                    label: 'Register',
                    onTap: () {
                      setState(() {
                        _isLoginFlow = false;
                        _isSelectionVisible = false;
                        _statusMessage = '';
                      });
                    },
                  ),
                ] else ...[
                  if (!_isLoginFlow) ...[
                    GlassInput(controller: _nameController, hintText: 'Name'),
                    const SizedBox(height: 20),
                    GlassInput(
                      controller: _phoneController,
                      hintText: 'Phone Number',
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),
                  ],
                  GlassInput(
                    controller: _emailController,
                    hintText: 'Email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),
                  GlassInput(
                    controller: _passwordController,
                    hintText: 'Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 35),
                  
                  GlassButton(
                    label: _isLoginFlow ? 'Login' : 'Register',
                    onTap: () => _handleAuth(isLogin: _isLoginFlow),
                  ),
                  
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
                  const CircularProgressIndicator(color: AppColors.neonCyan),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // REMOVED: Local glass helpers (now using global components)

  Future<void> _handleAuth({required bool isLogin}) async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _showAuthFeedback(title: 'Input Required', message: 'Please fill in email and password');
      return;
    }
    
    if (!isLogin && (name.isEmpty || phone.isEmpty)) {
      _showAuthFeedback(title: 'Input Required', message: 'Please fill in all fields');
      return;
    }

    if (pass.length < 6) {
      _showAuthFeedback(title: 'Invalid Password', message: 'Password must be at least 6 characters');
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
        
        // IMPORTANT: Set name/phone for NEW registration before pushing to cloud
        StorageService.userName = name;
        StorageService.userPhone = phone;
        StorageService.userPassword = pass;
        StorageService.isFirstLaunch = false;
        
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
        setState(() => _isLoading = false);
        _showAuthFeedback(
          title: isLogin ? 'Login Failed' : 'Registration Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showAuthFeedback(title: 'Input Required', message: 'Enter email to reset password');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      await FirebaseService.sendPasswordReset(email);
      if (mounted) {
        setState(() => _isLoading = false);
        _showAuthFeedback(
          title: 'Reset Link Sent',
          message: 'Please check your inbox at $email',
          isError: false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showAuthFeedback(title: 'Error', message: 'Failed to send reset link');
      }
    }
  }
}
