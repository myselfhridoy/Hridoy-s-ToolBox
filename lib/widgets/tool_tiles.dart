import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/tokens.dart';
import 'favorite_button.dart';
import 'glass_card.dart';

/// গ্রিডে ব্যবহারের কার্ড (Home, Library)।
class ToolCard extends StatelessWidget {
  final ToolPlugin tool;
  const ToolCard({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassCard(
      radius: AppRadius.xl,
      onTap: () => context.push('/tool/${tool.id}'),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(tool.icon, size: AppSizes.iconLg),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    tool.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: FavoriteButton(toolId: tool.id),
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
      onTap: () => context.push('/tool/${tool.id}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.xs,
            top: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(tool.icon, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tool.name, style: t.titleMedium),
                    if (tool.categories.isNotEmpty)
                      Text(
                        tool.categories.join(' · '),
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              FavoriteButton(toolId: tool.id),
            ],
          ),
        ),
      ),
    );
  }
}
