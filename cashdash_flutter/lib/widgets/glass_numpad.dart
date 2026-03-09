import 'package:flutter/material.dart';

class GlassNumpad extends StatelessWidget {
  final Function(String) onNumberTap;
  final VoidCallback onBackspace;
  final VoidCallback onAction;
  final IconData actionIcon;
  final double spacing;

  const GlassNumpad({
    super.key,
    required this.onNumberTap,
    required this.onBackspace,
    required this.onAction,
    required this.actionIcon,
    this.spacing = 20,
  });

  Widget _buildKey(Widget child, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          // Layer 1: Base Glass (bg_glass_3d_keypad.xml)
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.12), // #1AFFFFFF
              Colors.white.withOpacity(0.04), // #08FFFFFF
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Layer 2: Top Gloss Highlight
            Positioned(
              top: 0,
              left: 4,
              right: 4,
              height: 25,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
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
            Center(child: child),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.3, // Slightly wider than tall for that specific ovalish-circle look
        mainAxisSpacing: spacing == 20 ? 15 : spacing,
        crossAxisSpacing: spacing == 20 ? 15 : spacing,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        Widget child;
        VoidCallback? tap;

        if (index < 9) {
          final num = (index + 1).toString();
          child = Text(num, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold));
          tap = () => onNumberTap(num);
        } else if (index == 9) {
          child = const Icon(Icons.backspace_outlined, color: Colors.white, size: 28);
          tap = onBackspace;
        } else if (index == 10) {
          child = const Text('0', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold));
          tap = () => onNumberTap('0');
        } else {
          child = Icon(actionIcon, color: Colors.white, size: 28);
          tap = onAction;
        }
        return _buildKey(child, onTap: tap);
      },
    );
  }
}
