import 'package:flutter/material.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';
import '../core/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/tool_tiles.dart';

class RecentScreen extends StatelessWidget {
  const RecentScreen({super.key});

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
              final tools = UsageStore.instance.recents
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
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Semantics(
                            header: true,
                            child: Text('Recent', style: t.headlineMedium),
                          ),
                          if (tools.isNotEmpty)
                            TextButton.icon(
                              onPressed: UsageStore.instance.clearRecents,
                              icon: const Icon(Icons.delete_outline, size: 20),
                              label: const Text('Clear'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (tools.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.history_rounded,
                        title: 'No recent tools',
                        subtitle: 'Open a tool to see it here',
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
