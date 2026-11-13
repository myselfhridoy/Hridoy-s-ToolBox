import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/tokens.dart';
import 'favorite_button.dart';
import 'glass_card.dart';

class _ToolIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;

  const _ToolIconBadge({
    required this.icon,
    this.size = 42,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.secondary.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Icon(icon, size: iconSize, color: AppColors.primary),
    );
  }
}

/// গ্রিডে ব্যবহারের কমপ্যাক্ট কার্ড (Home, Library)।
class ToolCard extends StatelessWidget {
  final ToolPlugin tool;
  const ToolCard({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final category = tool.categories.isNotEmpty ? tool.categories.first : null;

    return GlassCard(
      radius: AppRadius.lg,
      onTap: () => context.push('/tool/${tool.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ToolIconBadge(icon: tool.icon, size: 40, iconSize: 21),
                const Spacer(),
                FavoriteButton(toolId: tool.id, size: 19),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Text(
                tool.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.titleMedium?.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (category != null) ...[
              const SizedBox(height: 2),
              Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// লিস্টে ব্যবহারের টাইল (Favorites, Recent, Search)।
class ToolListTile extends StatelessWidget {
  final ToolPlugin tool;
  const ToolListTile({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassCard(
      radius: AppRadius.md,
      onTap: () => context.push('/tool/${tool.id}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 8,
          ),
          child: Row(
            children: [
              _ToolIconBadge(icon: tool.icon, size: 40, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.name,
                      style: t.titleMedium?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tool.categories.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        tool.categories.join(' · '),
                        style: t.bodySmall?.copyWith(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              FavoriteButton(toolId: tool.id, size: 20),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
