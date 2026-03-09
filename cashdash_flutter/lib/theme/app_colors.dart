import 'package:flutter/material.dart';

class AppColors {
  // Main background (bg_main_gradient.xml)
  static const Color bgStartColor = Color(0xFF0D1B6E);
  static const Color bgCenterColor = Color(0xFF010A43);
  static const Color bgEndColor = Color(0xFF000520);

  // Glassmorphism (bg_glass_3d.xml)
  static const Color glassStart = Color(0x1AFFFFFF);
  static const Color glassEnd = Color(0x08FFFFFF);
  static const Color glassStroke = Color(0x40FFFFFF);
  static const Color glassHighlightStart = Color(0x20FFFFFF);
  static const Color glassHighlightEnd = Color(0x00FFFFFF);

  // 3D Card (bg_3d_card.xml)
  static const Color cardStart = Color(0xFF1A2D8A);
  static const Color cardEnd = Color(0xFF07103D);
  static const Color cardStroke = Color(0xFF37478A);
  static const Color cardGlossStart = Color(0x40FFFFFF);
  static const Color cardShadow = Color(0x05000000);

  // Transaction Glass (bg_glass_transaction.xml)
  static const Color txGlassBase = Color(0x25FFFFFF);
  static const Color txGlassRim = Color(0x30FFFFFF);

  // Other specific colors from XML
  static const Color lightBlueText = Color(0xFFB0C8FF); // tvNextMoney, etc.
  static const Color subtitleBlue = Color(0xFFB0C4FF); // tvLabel, item_category subtitle
  static const Color neonBlue = Color(0xFF00BFFF);
  static const Color neonCyan = Color(0xFF8BF7E6); // progress bar tint
  static const Color errorRed = Color(0xFFFF6B6B);
  static const Color amountRed = Color(0xFFFF4D4D);
  static const Color transparent = Colors.transparent;
  
  // Bottom Nav (bg_3d_bottom_nav.xml)
  static const Color navGlossStart = Color(0xFF506AAA); // Glossy top bevel
  static const Color navGlossEnd = Color(0xFF0A1656);   // Deep transition
  static const Color navBodyStart = Color(0xFF122070);  // Main body lit top
  static const Color navBodyEnd = Color(0xFF060E3A);    // Shadowed base

  static const LinearGradient mainBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      bgStartColor,
      bgCenterColor,
      bgEndColor,
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient glassInputGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1A3A), Color(0xFF070B1A)],
  );
}
