import 'package:flutter/material.dart';
import '../theme/app_styles.dart';

class DittoDropdown {
  static void show({
    required BuildContext context,
    required Rect anchorRect,
    required List<String> items,
    required Function(String) onSelected,
  }) {
    final OverlayState overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismissible background
          GestureDetector(
            onTap: () => overlayEntry.remove(),
            child: Container(
              color: Colors.transparent,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
            ),
          ),
          // Gradient Dropdown
          Positioned(
            left: anchorRect.left,
            top: anchorRect.bottom + 8,
            width: 180, // Matches native screenshot scale
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.95 + (0.05 * value),
                      alignment: Alignment.topLeft,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  decoration: AppStyles.glassInputDecoration.copyWith(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      AppStyles.glassInputOverlay,
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: items.map((item) {
                            return InkWell(
                              onTap: () {
                                onSelected(item);
                                overlayEntry.remove();
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlayState.insert(overlayEntry);
  }
}
