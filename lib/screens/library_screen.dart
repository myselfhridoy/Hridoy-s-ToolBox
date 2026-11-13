import 'package:flutter/material.dart';
import '../core/plugin/plugin_registry.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/tokens.dart';
import '../widgets/glass_card.dart';
import '../widgets/tool_tiles.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _selectedCategory;

  /// ডিফল্টভাবে খালি — অর্থাৎ সব ক্যাটাগরি collapsed অবস্থায় থাকবে।
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tools = PluginRegistry.instance.plugins;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth >= 430 ? 5 : 4;

    final grouped = <String, List<ToolPlugin>>{};
    for (final tool in tools) {
      final cats =
          tool.categories.isEmpty ? ['Uncategorized'] : tool.categories;
      for (final cat in cats) {
        grouped.putIfAbsent(cat, () => []).add(tool);
      }
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    final allCategories = grouped.keys.toList()..sort();
    final categoriesToShow =
        _selectedCategory == null ? allCategories : [_selectedCategory!];

    final areAllCollapsed = allCategories.isNotEmpty &&
        allCategories.every((cat) => !_expanded.contains(cat));

    return Scaffold(
      body: AmbientBackdrop(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Library', style: t.headlineMedium),
                      ),
                      const Spacer(),
                      if (allCategories.isNotEmpty)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            backgroundColor: AppColors.fieldFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              side: const BorderSide(
                                color: AppColors.glassBorder,
                              ),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              if (areAllCollapsed) {
                                _expanded.addAll(allCategories);
                              } else {
                                _expanded.clear();
                              }
                            });
                          },
                          icon: Icon(
                            areAllCollapsed
                                ? Icons.unfold_more_rounded
                                : Icons.unfold_less_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          label: Text(
                            areAllCollapsed ? 'Expand all' : 'Collapse all',
                            style: t.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
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
                          onTap: () => setState(() {
                            _selectedCategory = cat;
                            _expanded.add(cat);
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              for (final cat in categoriesToShow)
                ..._buildCategory(
                  context,
                  cat,
                  grouped[cat] ?? [],
                  crossAxisCount,
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCategory(
    BuildContext context,
    String category,
    List<ToolPlugin> tools,
    int crossAxisCount,
  ) {
    final t = Theme.of(context).textTheme;
    final expanded = _expanded.contains(category);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Semantics(
            button: true,
            expanded: expanded,
            label: '$category, ${tools.length} tools',
            excludeSemantics: true,
            child: GlassCard(
              radius: AppRadius.md,
              onTap: () => setState(() {
                if (expanded) {
                  _expanded.remove(category);
                } else {
                  _expanded.add(category);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      category,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${tools.length}',
                        style: t.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (expanded)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.84,
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
