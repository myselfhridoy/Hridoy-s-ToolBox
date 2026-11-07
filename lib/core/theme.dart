import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B0F1A),
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFF6C8CFF),
        secondary: const Color(0xFFB38CFF),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }
}
