import 'package:flutter/material.dart';

class GlassInput extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;

  const GlassInput({
    super.key,
    this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        // Deep background with glass tint
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A2D8A),
            Color(0xFF101B54),
          ],
        ),
        // Frosted overlay and glowing rim light (Top & Sides)
        // using border for the rim light
        border: const Border(
          top: BorderSide(color: Color(0x40FFFFFF), width: 1.5),
          left: BorderSide(color: Color(0x40FFFFFF), width: 1.5),
          right: BorderSide(color: Color(0x40FFFFFF), width: 1.5),
          bottom: BorderSide(color: Colors.transparent, width: 0),
        ),
      ),
      child: Stack(
        children: [
          // Frosted overlay via Solid Color
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x20FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Actual input child
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: controller,
                obscureText: obscureText,
                keyboardType: keyboardType,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(color: Color(0xFF9EB2FF), fontSize: 16),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
