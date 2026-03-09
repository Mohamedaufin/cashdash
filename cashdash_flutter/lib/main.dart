import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_colors.dart';
import 'splash_screen.dart';
import 'theme/ditto_transitions.dart';
import 'firebase_options.dart';

import 'package:firebase_core/firebase_core.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await StorageService.init();
  runApp(const CashDashApp());
}

class CashDashApp extends StatelessWidget {
  const CashDashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CashDash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.transparent,
        textTheme: GoogleFonts.outfitTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: DittoTransitionsBuilder(),
            TargetPlatform.iOS: DittoTransitionsBuilder(),
          },
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
