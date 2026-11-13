import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';
import '../core/tokens.dart';
import '../widgets/glass_card.dart';
import '../widgets/tool_tiles.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tools = PluginRegistry.instance.plugins;
    final byId = {for (final p in tools) p.id: p};

    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: UsageStore.instance,
            builder: (context, _) {
              final quickIds = <String>{
                ...UsageStore.instance.favorites,
                ...UsageStore.instance.recents,
              };
              final quickTools = quickIds
                  .map((id) => byId[id])
                  .whereType<ToolPlugin>()
                  .take(6)
                  .toList();

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.primary,
                                      AppColors.secondary,
                                    ],
                                  ),
                                ),
                                child: const Icon(
                                  Icons.handyman_rounded,
                                  color: Color(0xFF070B14),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(
                                      header: true,
                                      child: Text(
                                        "Hridoy's ToolBox",
                                        style: t.headlineMedium?.copyWith(
                                          fontSize: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Modular developer utilities',
                                      style: t.bodySmall?.copyWith(
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  '${tools.length} tools',
                                  style: t.labelSmall?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _SearchBar(onTap: () => context.push('/search')),
                          if (quickTools.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xl),
                            Semantics(
                              header: true,
                              child: Text('Quick Access', style: t.titleLarge),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              height: 44,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: quickTools.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: AppSpacing.sm),
                                itemBuilder: (context, i) {
                                  final qt = quickTools[i];
                                  final isFav =
                                      UsageStore.instance.isFavorite(qt.id);
                                  return GlassCard(
                                    radius: AppRadius.md,
                                    onTap: () => context.push('/tool/${qt.id}'),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            qt.icon,
                                            size: 16,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 7),
                                          Text(
                                            qt.name,
                                            style: t.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (isFav) ...[
                                            const SizedBox(width: 6),
                                            const Icon(
                                              Icons.star_rounded,
                                              size: 14,
                                              color: AppColors.star,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          Semantics(
                            header: true,
                            child: Text('All Tools', style: t.titleLarge),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.xl,
                      AppSpacing.xxl,
                    ),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.28,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ToolCard(tool: tools[i]),
                        childCount: tools.length,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search tools',
      excludeSemantics: true,
      child: GlassCard(
        radius: AppRadius.md,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search tools, tags, categories…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                ),
                const Icon(
                  Icons.tune_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
