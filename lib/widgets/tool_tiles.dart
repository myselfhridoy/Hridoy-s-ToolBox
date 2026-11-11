import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/tokens.dart';
import 'favorite_button.dart';
import 'glass_card.dart';

/// গ্রিডে ব্যবহারের কমপ্যাক্ট কার্ড (Home, Library)।
class ToolCard extends StatelessWidget {
  final ToolPlugin tool;
  const ToolCard({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassCard(
      radius: AppRadius.lg,
      onTap: () => context.push('/tool/${tool.id}'),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tool.icon, size: 26, color: AppColors.primary),
                  const SizedBox(height: 6),
                  Text(
                    tool.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: FavoriteButton(toolId: tool.id, size: 18),
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
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          child: Row(
            children: [
              Icon(tool.icon, size: 22, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.name,
                      style: t.titleMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tool.categories.isNotEmpty)
                      Text(
                        tool.categories.join(' · '),
                        style: t.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              FavoriteButton(toolId: tool.id, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
