import 'package:flutter/material.dart';
import '../core/plugin/tool_plugin.dart';
import '../core/storage/usage_store.dart';

/// টুল পেজের চারপাশে wrapper — খোলা মাত্রই Recent-এ রেকর্ড করে।
class ToolHost extends StatefulWidget {
  final ToolPlugin tool;
  const ToolHost({super.key, required this.tool});

  @override
  State<ToolHost> createState() => _ToolHostState();
}

class _ToolHostState extends State<ToolHost> {
  @override
  void initState() {
    super.initState();
    UsageStore.instance.recordUsage(widget.tool.id);
  }

  @override
  Widget build(BuildContext context) => widget.tool.buildPage(context);
}
