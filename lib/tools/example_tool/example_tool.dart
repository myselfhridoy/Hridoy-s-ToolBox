import 'package:flutter/material.dart';
import '../../core/plugin/tool_plugin.dart';

class ExampleTool implements ToolPlugin {
  @override
  String get id => 'example_tool';

  @override
  String get name => 'Example';

  @override
  IconData get icon => Icons.science_outlined;

  @override
  List<String> get categories => ['Demo'];

  @override
  List<String> get tags => ['example', 'demo'];

  @override
  Widget buildPage(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Example Tool')),
      body: const Center(child: Text('This is a tool page.')),
    );
  }
}
