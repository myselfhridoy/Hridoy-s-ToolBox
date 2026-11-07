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
            final allTools = PluginRegistry.instance.plugins;
            final byId = {for (final t in allTools) t.id: t};
            final favorites = UsageStore.instance.favorites
                .map((id) => byId[id])
                .whereType<ToolPlugin>()
                .toList();
            final recents = UsageStore.instance.recents
                .map((id) => byId[id])
                .whereType<ToolPlugin>()
                .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Hridoy's ToolBox",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${allTools.length} tools ready',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SearchBar(onTap: () => context.push('/search')),

                  if (favorites.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const _SectionHeader(title: 'Favorites'),
                    const SizedBox(height: 10),
                    _HorizontalTools(tools: favorites),
                  ],

                  if (recents.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionHeader(title: 'Recent'),
                        TextButton(
                          onPressed: () =>
                              UsageStore.instance.clearRecents(),
                          child: Text(
                            'Clear',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _HorizontalTools(tools: recents),
                  ],

                  const SizedBox(height: 24),
                  const _SectionHeader(title: 'All Tools'),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: allTools.length,
                    itemBuilder: (context, index) =>
                        _ToolCard(tool: allTools[index]),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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

class _HorizontalTools extends StatelessWidget {
  final List<ToolPlugin> tools;
  const _HorizontalTools({required this.tools});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 110,
          child: _ToolCard(tool: tools[i]),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolPlugin tool;
  const _ToolCard({required this.tool});

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
                onPressed: () =>
                    UsageStore.instance.toggleFavorite(tool.id),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
