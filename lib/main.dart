import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/plugin/plugin_registry.dart';
import 'core/storage/usage_store.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'tools/example_tool/example_tool.dart';
import 'widgets/tool_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UsageStore.instance.init();
  PluginRegistry.instance.registerAll([
    ExampleTool(),
  ]);
  runApp(const HridoysToolboxApp());
}

class HridoysToolboxApp extends StatelessWidget {
  const HridoysToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
        ...PluginRegistry.instance.plugins.map(
          (tool) => GoRoute(
            path: '/tool/${tool.id}',
            builder: (context, state) => ToolHost(tool: tool),
          ),
        ),
      ],
    );

    return MaterialApp.router(
      title: "Hridoy's ToolBox",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}
