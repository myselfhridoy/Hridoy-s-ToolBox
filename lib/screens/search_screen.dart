import 'package:flare_glass/flare_glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ToolPlugin> _results() {
    final all = PluginRegistry.instance.plugins;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((t) {
      if (t.name.toLowerCase().contains(q)) return true;
      if (t.id.toLowerCase().contains(q)) return true;
      if (t.tags.any((tag) => tag.toLowerCase().contains(q))) return true;
      if (t.categories.any((c) => c.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search tools…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: results.isEmpty
          ? const Center(
              child: Text('No tools found'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final tool = results[i];
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
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
                                      color: Colors.white
                                          .withValues(alpha: 0.5),
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
                            onPressed: () async {
                              await UsageStore.instance
                                  .toggleFavorite(tool.id);
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
