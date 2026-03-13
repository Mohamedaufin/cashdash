import 'package:flutter/material.dart';

class GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int maxLines;
  final double height;

  const GlassInput({
    super.key,
    required this.controller,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.height = 65,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: maxLines > 1 ? null : height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Deep background with glass tint (bg_glass_input.xml)
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A2D8A), Color(0xFF101B54)],
        ),
        boxShadow: [
          // Frosted overlay (#20FFFFFF)
          BoxShadow(
            color: Colors.white.withOpacity(0.12),
            spreadRadius: 0,
            blurRadius: 0,
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.25), // Glowing Rim Light (#40FFFFFF)
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        maxLines: maxLines,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: prefixIcon != null
              ? IconTheme(
                  data: IconThemeData(color: Colors.white.withOpacity(0.6)),
                  child: prefixIcon!,
                )
              : null,
          suffixIcon: suffixIcon != null
              ? IconTheme(
                  data: IconThemeData(color: Colors.white.withOpacity(0.6)),
                  child: suffixIcon!,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
