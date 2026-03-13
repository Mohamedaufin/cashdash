import 'package:flutter/material.dart';

class TransactionDialog extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;

  const TransactionDialog({
    super.key,
    required this.child,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Container(
            width: width ?? MediaQuery.of(context).size.width * 0.85,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Deep Shadow for elevation (Shifted 4dp right and down)
                Positioned.fill(
                  left: 6,
                  top: 6,
                  right: -2,
                  bottom: -2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x40000000),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                // 2. Main Background Gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A2D8A), Color(0xFF07103D)],
                      stops: [0.0, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF4A5FA1),
                      width: 1.5,
                    ),
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void show(BuildContext context, {required Widget child}) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => TransactionDialog(child: child),
    );
  }
}
