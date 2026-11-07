import 'package:flare_glass/flare_glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

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
            final tools = UsageStore.instance.favorites
                .map((id) => byId[id])
                .whereType<ToolPlugin>()
                .toList();

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      'Favorites',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
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
                            Icons.star_border,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No favorites yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap ⭐ on any tool',
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

class ToolListTile extends StatelessWidget {
  final ToolPlugin tool;
  const ToolListTile({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final isFav = UsageStore.instance.isFavorite(tool.id);
    return GestureDetector(
      onTap: () => context.push('/tool/${tool.id}'),
      child: FlareGlass(
        blurX: 16,
        blurY: 16,
        borderRadius: BorderRadius.circular(16),
        tintColor: Colors.white.withValues(alpha: 0.06),
        borderColor: Colors.white.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(tool.icon, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tool.categories.isNotEmpty)
                      Text(
                        tool.categories.join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  size: 20,
                  color: isFav
                      ? Colors.amberAccent
                      : Colors.white.withValues(alpha: 0.5),
                ),
                onPressed: () => UsageStore.instance.toggleFavorite(tool.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
