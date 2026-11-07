import 'tool_plugin.dart';

class PluginRegistry {
  PluginRegistry._();
  static final PluginRegistry instance = PluginRegistry._();

  final List<ToolPlugin> _plugins = [];

  List<ToolPlugin> get plugins => List.unmodifiable(_plugins);

  void register(ToolPlugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) return;
    _plugins.add(plugin);
  }

  void registerAll(List<ToolPlugin> list) => list.forEach(register);
}
