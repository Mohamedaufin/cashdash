import 'package:flutter/material.dart';

class DittoTransitionsBuilder extends PageTransitionsBuilder {
  const DittoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 250ms Slide In from Right transition (default forward)
    // and Slide Out to Left
    
    // Note: To perfectly match native "slide_in_left" vs "slide_in_right" 
    // we would need to check the direction, but typically "forward" is slide in from right.
    
    final slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    ));

    return SlideTransition(
      position: slideAnimation,
      child: child,
    );
  }
}

/// A specialized custom page route for transitions that need specific durations
class DittoPageRoute<T> extends MaterialPageRoute<T> {
  DittoPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);
}
