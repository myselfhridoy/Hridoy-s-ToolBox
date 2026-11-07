import 'package:flare_glass/flare_glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: UsageStore.instance,
          builder: (context, _) {
            final tools = PluginRegistry.instance.plugins;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Hridoy's ToolBox",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tools.length} tools ready',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SearchBar(onTap: () => context.push('/search')),
                        const SizedBox(height: 20),
                        const Text(
                          'All Tools',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.2,
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
    );
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: FlareGlass(
        blurX: 18,
        blurY: 18,
        borderRadius: BorderRadius.circular(16),
        tintColor: Colors.white.withValues(alpha: 0.08),
        borderColor: Colors.white.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: Colors.white.withValues(alpha: 0.7),
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Search tools…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ToolCard extends StatelessWidget {
  final ToolPlugin tool;
  const ToolCard({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final isFav = UsageStore.instance.isFavorite(tool.id);
    return GestureDetector(
      onTap: () => context.push('/tool/${tool.id}'),
      child: FlareGlass(
        blurX: 18,
        blurY: 18,
        borderRadius: BorderRadius.circular(24),
        tintColor: Colors.white.withValues(alpha: 0.08),
        borderColor: Colors.white.withValues(alpha: 0.2),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tool.icon, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      tool.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
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
              child: IconButton(
                iconSize: 18,
                splashRadius: 16,
                icon: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  color: isFav
                      ? Colors.amberAccent
                      : Colors.white.withValues(alpha: 0.5),
                ),
                onPressed: () => UsageStore.instance.toggleFavorite(tool.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
