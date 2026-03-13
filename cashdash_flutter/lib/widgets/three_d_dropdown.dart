import 'package:flutter/material.dart';
import 'dart:ui';

class ThreeDDropdown extends StatelessWidget {
  final String text;
  final double width;
  final double height;
  final VoidCallback onTap;

  const ThreeDDropdown({
    super.key,
    required this.text,
    required this.width,
    this.height = 52,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // 1. Deep Shadow for elevation (Match native bg_3d_dropdown item 1)
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              offset: const Offset(4, 4),
              blurRadius: 0,
            ),
          ],
          // 2. High-fidelity Outline (Ensures it's drawn on top and throughout)
          border: Border.all(
            color: const Color(0xFF4A5FA1).withOpacity(0.8),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Stack(
              children: [
                // 3. Glassy Gradient Core
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF1A2D8A).withOpacity(0.85),
                        const Color(0xFF07103D).withOpacity(0.85),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
                // 4. Top Bevel Highlight (Match native bg_3d_dropdown item 3)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: height * 0.5,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.35),
                          Colors.white.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // Text Content
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            offset: Offset(0, 2),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
