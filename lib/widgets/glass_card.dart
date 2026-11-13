import 'package:flare_glass/flare_glass.dart';
import 'package:flutter/material.dart';
import '../core/tokens.dart';

/// Glass-style কার্ড — subtle top sheen ও ripple feedback সহ।
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = AppRadius.lg,
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return FlareGlass(
      blurX: 18,
      blurY: 18,
      borderRadius: r,
      tintColor: AppColors.glassTint,
      borderColor: borderColor ?? AppColors.glassBorder,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.glassHighlight,
              Colors.transparent,
            ],
            stops: [0.0, 0.55],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: r,
            splashColor: AppColors.primary.withValues(alpha: 0.12),
            highlightColor: AppColors.primary.withValues(alpha: 0.06),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// ডার্ক ব্যাকগ্রাউন্ডে সূক্ষ্ম ambient glow যোগ করে, যাতে GlassCard-এর blur ফুটে ওঠে।
class AmbientBackdrop extends StatelessWidget {
  final Widget child;
  const AmbientBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.85, -0.95),
                radius: 1.15,
                colors: [
                  AppColors.primaryGlow,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.95, -0.45),
                radius: 1.0,
                colors: [
                  AppColors.secondaryGlow,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
