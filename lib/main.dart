import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/plugin/plugin_registry.dart';
import 'core/storage/github_token_store.dart';
import 'core/storage/usage_store.dart';
import 'core/theme.dart';
import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/recent_screen.dart';
import 'screens/search_screen.dart';
import 'tools/gittomd/gittomd_tool.dart';
import 'tools/html_parser/html_parser_tool.dart';
import 'tools/iptv_finder/iptv_finder_tool.dart';
import 'widgets/app_shell.dart';
import 'widgets/tool_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UsageStore.instance.init();
  await GitHubTokenStore.instance.load();
  PluginRegistry.instance.registerAll([
    HtmlParserTool(),
    GittomdTool(),
    IptvFinderTool(),
  ]);
  runApp(const HridoysToolboxApp());
}

class HridoysToolboxApp extends StatelessWidget {
  const HridoysToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/home',
                builder: (_, __) => const HomeScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/library',
                builder: (_, __) => const LibraryScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/favorites',
                builder: (_, __) => const FavoritesScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/recent',
                builder: (_, __) => const RecentScreen(),
              ),
            ]),
          ],
        ),
        GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        ...PluginRegistry.instance.plugins.map(
          (tool) => GoRoute(
            path: '/tool/${tool.id}',
            builder: (_, __) => ToolHost(tool: tool),
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
