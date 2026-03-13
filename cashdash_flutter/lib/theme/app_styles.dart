import 'package:flutter/material.dart';

class AppStyles {
  /// bg_glass_input.xml parity
  static BoxDecoration glassInputDecoration = BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1A2D8A), Color(0xFF101B54)],
    ),
    border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
  );

  static Widget glassInputOverlay = Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white.withOpacity(0.12), // 20% in XML might be too much for readability, using 12% as a balance
    ),
  );

  /// bg_transaction.xml parity
  static BoxDecoration transactionDecoration = BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1A2D8A), Color(0xFF07103D)],
      stops: [0.0, 1.0],
    ),
    border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.0),
    boxShadow: const [
      BoxShadow(
        color: Color(0x40000000),
        offset: Offset(4, 4),
        blurRadius: 0,
      ),
    ],
  );

  /// bg_3d_card.xml parity
  static BoxDecoration threeDCardDecoration = BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1A2D8A), Color(0xFF07103D)],
    ),
    border: Border.all(color: const Color(0xFF37478A), width: 1.0),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0D000000), // 05 opacity in XML
        offset: Offset(4, 4),
        blurRadius: 0,
      ),
    ],
  );

  static Widget cardHighlight = Positioned(
    top: 0,
    left: 4,
    right: 4,
    height: 40,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.25),
            Colors.transparent,
          ],
        ),
      ),
    ),
  );
}
