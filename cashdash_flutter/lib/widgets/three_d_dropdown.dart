import 'package:flutter/material.dart';

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
          // Deep Shadow for elevation (Item 1 in XML)
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              offset: const Offset(4, 4),
              blurRadius: 0, // Solid shadow in XML
            ),
          ],
        ),
        child: Stack(
          children: [
            // Main Background Gradient & Stroke (Item 2 in XML)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A2D8A), Color(0xFF07103D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [0.0, 1.0],
                ),
                border: Border.all(
                  color: const Color(0xFF4A5FA1),
                  width: 1.5,
                ),
              ),
            ),
            // Top Bevel Highlight (Item 3 in XML)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: height * 0.6, // Top half roughly
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.3),
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
    );
  }
}
