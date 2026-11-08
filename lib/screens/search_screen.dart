import 'package:flutter/material.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../widgets/empty_state.dart';
import '../widgets/tool_tiles.dart';

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
          textInputAction: TextInputAction.search,
          style: Theme.of(context).textTheme.bodyLarge,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search tools…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: results.isEmpty
          ? const EmptyState(
              icon: Icons.search_off,
              title: 'No tools found',
              subtitle: 'Try a different keyword',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => ToolListTile(tool: results[i]),
            ),
    );
  }
}
