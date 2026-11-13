import 'package:flutter/material.dart';

/// Design tokens — সব রং, স্পেসিং, সাইজ এক জায়গায়।
class AppColors {
  AppColors._();

  // Base surfaces
  static const bg = Color(0xFF090D16);
  static const navBg = Color(0xFF0F1422);
  static const surfaceElevated = Color(0xFF151C2E);

  // Brand accents
  static const primary = Color(0xFF6C8CFF);
  static const secondary = Color(0xFFB38CFF);
  static const primaryGlow = Color(0x2E6C8CFF); // 18%
  static const secondaryGlow = Color(0x24B38CFF); // 14%

  // Text (contrast ≥ 4.5:1 on bg)
  static const textPrimary = Color(0xFFF4F6FB);
  static const textSecondary = Color(0xFFC3C7D4);
  static const textMuted = Color(0xFF8E95A8);

  // Glass surfaces & borders
  static const glassTint = Color(0x14FFFFFF); // white 8%
  static const glassHighlight = Color(0x1FFFFFFF); // white 12%
  static const glassBorder = Color(0x29FFFFFF); // white 16%
  static const glassBorderStrong = Color(0x47FFFFFF); // white 28%
  static const fieldFill = Color(0x0FFFFFFF); // white 6%

  // Semantic
  static const star = Color(0xFFFFD166);
  static const error = Color(0xFFFF7A7A);
  static const success = Color(0xFF4ADE80);
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

class AppSizes {
  AppSizes._();

  static const double minTouch = 48;
  static const double icon = 24;
  static const double iconLg = 32;
  static const double minText = 12;
}
