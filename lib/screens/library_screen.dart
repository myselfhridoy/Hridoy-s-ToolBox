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

    final areAllCollapsed = allCategories.isNotEmpty &&
        allCategories.every((cat) => _collapsed.contains(cat));

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
                            side: const BorderSide(color: AppColors.glassBorder),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            if (areAllCollapsed) {
                              _collapsed.clear();
                            } else {
                              _collapsed.addAll(allCategories);
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
                          _collapsed.remove(cat); // ensure selected is expanded
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
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
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xs,
          ),
          child: Semantics(
            button: true,
            expanded: !collapsed,
            label: '$category, ${tools.length} tools',
            excludeSemantics: true,
            child: GlassCard(
              radius: AppRadius.md,
              onTap: () => setState(() {
                if (collapsed) {
                  _collapsed.remove(category);
                } else {
                  _collapsed.add(category);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.25,
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
      if (!collapsed)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xs,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
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
