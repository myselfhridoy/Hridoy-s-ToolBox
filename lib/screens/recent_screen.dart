import 'package:flutter/material.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';
import 'favorites_screen.dart';

class RecentScreen extends StatelessWidget {
  const RecentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: UsageStore.instance,
          builder: (context, _) {
            final byId = {
              for (final t in PluginRegistry.instance.plugins) t.id: t
            };
            final tools = UsageStore.instance.recents
                .map((id) => byId[id])
                .whereType<ToolPlugin>()
                .toList();

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (tools.isNotEmpty)
                          TextButton.icon(
                            onPressed: () =>
                                UsageStore.instance.clearRecents(),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Clear'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (tools.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No recent tools',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Open a tool to see it here',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    sliver: SliverList.separated(
                      itemCount: tools.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          ToolListTile(tool: tools[i]),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
