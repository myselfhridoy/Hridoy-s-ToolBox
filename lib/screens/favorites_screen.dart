import 'package:flutter/material.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';
import '../core/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/tool_tiles.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: UsageStore.instance,
            builder: (context, _) {
              final byId = {
                for (final p in PluginRegistry.instance.plugins) p.id: p,
              };
              final tools = UsageStore.instance.favorites
                  .map((id) => byId[id])
                  .whereType<ToolPlugin>()
                  .toList();

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text('Favorites', style: t.headlineMedium),
                      ),
                    ),
                  ),
                  if (tools.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.star_border_rounded,
                        title: 'No favorites yet',
                        subtitle: 'Tap the star on any tool',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      sliver: SliverList.separated(
                        itemCount: tools.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) => ToolListTile(tool: tools[i]),
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
