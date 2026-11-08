import 'package:flutter/material.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/tokens.dart';
import '../widgets/tool_tiles.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _selectedCategory;
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tools = PluginRegistry.instance.plugins;

    final grouped = <String, List<ToolPlugin>>{};
    for (final tool in tools) {
      final cats =
          tool.categories.isEmpty ? ['Uncategorized'] : tool.categories;
      for (final cat in cats) {
        grouped.putIfAbsent(cat, () => []).add(tool);
      }
    }
    final allCategories = grouped.keys.toList()..sort();
    final categoriesToShow =
        _selectedCategory == null ? allCategories : [_selectedCategory!];

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Library', style: t.headlineMedium),
                    ),
                    const Spacer(),
                    Text(
                      '${tools.length} tools · ${allCategories.length} categories',
                      style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _selectedCategory == null,
                      onTap: () => setState(() => _selectedCategory = null),
                    ),
                    ...allCategories.map(
                      (cat) => _FilterChip(
                        label: cat,
                        selected: _selectedCategory == cat,
                        onTap: () => setState(() => _selectedCategory = cat),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final cat in categoriesToShow)
              ..._buildCategory(context, cat, grouped[cat] ?? []),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategory(
    BuildContext context,
    String category,
    List<ToolPlugin> tools,
  ) {
    final t = Theme.of(context).textTheme;
    final collapsed = _collapsed.contains(category);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Semantics(
            button: true,
            expanded: !collapsed,
            label: '$category, ${tools.length} tools',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() {
                if (collapsed) {
                  _collapsed.remove(category);
                } else {
                  _collapsed.add(category);
                }
              }),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: AppSizes.minTouch),
                child: Row(
                  children: [
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_right
                          : Icons.keyboard_arrow_down,
                      size: AppSizes.icon,
                    ),
                    const SizedBox(width: 6),
                    Text(category, style: t.titleLarge),
                    const Spacer(),
                    Text(
                      '${tools.length}',
                      style: t.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (!collapsed)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ToolCard(tool: tools[i]),
              childCount: tools.length,
            ),
          ),
        ),
    ];
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Center(
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      ),
    );
  }
}
