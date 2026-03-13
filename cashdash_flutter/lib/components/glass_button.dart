import 'package:flutter/material.dart';

class GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double height;
  final bool isSecondary;
  final Color? color;

  const GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 60,
    this.isSecondary = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Exact colors from bg_glass_3d_red.xml if color is redAccent
    final bool isRed = color == Colors.redAccent;
    
    final List<Color> gradientColors = isSecondary
        ? [Colors.transparent, Colors.transparent]
        : (isRed
            ? [const Color(0x40FF0000), const Color(0x10FF0000)]
            : (color != null
                ? [color!.withOpacity(0.8), color!]
                : [const Color(0xFF1E3A70), const Color(0xFF0A1640)]));

    final Color strokeColor = isSecondary
        ? Colors.white.withOpacity(0.1)
        : (isRed
            ? const Color(0x80FF4444)
            : (color != null
                ? color!.withOpacity(0.4)
                : const Color(0xFF3A6AFF).withOpacity(0.3)));

    final Color highlightColor = isRed
        ? const Color(0x30FFAAAA)
        : Colors.white.withOpacity(0.15);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height * 0.3), // Dynamic but consistent
          gradient: isSecondary
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
          color: isSecondary ? const Color(0x26FFFFFF) : null,
          border: Border.all(
            color: isSecondary ? Colors.white.withOpacity(0.12) : strokeColor,
            width: 1.2,
          ),
          boxShadow: isSecondary ? [] : [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: (color ?? const Color(0xFF3A6AFF)).withOpacity(0.1),
              blurRadius: 12,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Top Gloss Highlight (Layer 2 in XML)
            if (!isSecondary)
              Positioned(
                top: 0,
                left: 2,
                right: 2,
                height: height * 0.45,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(height * 0.3)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        highlightColor,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Center(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: height > 55 ? 18 : 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  shadows: isRed ? [const Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))] : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
