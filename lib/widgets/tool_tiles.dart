import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';
import '../core/tokens.dart';
import 'favorite_button.dart';
import 'glass_card.dart';

class _ToolIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final double radius;

  const _ToolIconBadge({
    required this.icon,
    this.size = 38,
    this.iconSize = 20,
    this.radius = AppRadius.sm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
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

/// ৪/৫ কলাম গ্রিডে ব্যবহারের কম্প্যাক্ট কার্ড (Home, Library)।
class ToolCard extends StatelessWidget {
  final ToolPlugin tool;
  const ToolCard({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassCard(
      radius: AppRadius.md,
      onTap: () => context.push('/tool/${tool.id}'),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ToolIconBadge(
                    icon: tool.icon,
                    size: 36,
                    iconSize: 19,
                    radius: 10,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tool.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelSmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 3,
            right: 3,
            child: ListenableBuilder(
              listenable: UsageStore.instance,
              builder: (context, _) {
                final fav = UsageStore.instance.isFavorite(tool.id);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => UsageStore.instance.toggleFavorite(tool.id),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      fav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 13,
                      color: fav
                          ? AppColors.star
                          : AppColors.textMuted.withValues(alpha: 0.55),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
              _ToolIconBadge(
                icon: tool.icon,
                size: 40,
                iconSize: 20,
                radius: AppRadius.md,
              ),
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
