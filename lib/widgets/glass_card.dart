import 'package:flare_glass/flare_glass.dart';
import 'package:flutter/material.dart';
import '../core/tokens.dart';

/// Glass-style কার্ড — ট্যাপ করলে ripple feedback দেয়।
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = AppRadius.lg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return FlareGlass(
      blurX: 16,
      blurY: 16,
      borderRadius: r,
      tintColor: AppColors.glassTint,
      borderColor: AppColors.glassBorder,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          child: child,
        ),
      ),
    );
  }
}
