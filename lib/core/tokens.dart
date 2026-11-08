import 'package:flutter/material.dart';

/// Design tokens — সব রং, স্পেসিং, সাইজ এক জায়গায়।
/// কম্পোনেন্টে সরাসরি Colors.white.withValues(...) না লিখে এগুলো ব্যবহার করুন।
class AppColors {
  AppColors._();

  static const bg = Color(0xFF0B0F1A);
  static const navBg = Color(0xFF111626);
  static const primary = Color(0xFF6C8CFF);
  static const secondary = Color(0xFFB38CFF);

  // টেক্সট (bg-এর ওপর কন্ট্রাস্ট ≥ 4.5:1)
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFC3C7D4); // ~11:1
  static const textMuted = Color(0xFF9CA1B0); // ~7:1

  // Glass surface
  static const glassTint = Color(0x14FFFFFF); // white 8%
  static const glassBorder = Color(0x33FFFFFF); // white 20%
  static const fieldFill = Color(0x0DFFFFFF); // white 5%

  // Semantic
  static const star = Colors.amberAccent;
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

  /// ন্যূনতম টাচ টার্গেট (Material: 48dp, গাইডলাইন ≥ 44)
  static const double minTouch = 48;
  static const double icon = 24;
  static const double iconLg = 32;

  /// body টেক্সটের সর্বনিম্ন সাইজ
  static const double minText = 12;
}
