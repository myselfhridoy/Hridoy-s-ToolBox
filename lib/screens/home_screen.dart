import 'package:flare_glass/flare_glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/plugin/plugin_registry.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final plugins = PluginRegistry.instance.plugins;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text(
                "Hridoy's ToolBox",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${plugins.length} tools ready',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: plugins.length,
                  itemBuilder: (context, index) {
                    final tool = plugins[index];
                    return GestureDetector(
                      onTap: () => context.push('/tool/${tool.id}'),
                      child: FlareGlass(
                        blurX: 18,
                        blurY: 18,
                        borderRadius: BorderRadius.circular(24),
                        tintColor: Colors.white.withValues(alpha: 0.08),
                        borderColor: Colors.white.withValues(alpha: 0.2),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(tool.icon, size: 34),
                              const SizedBox(height: 10),
                              Text(
                                tool.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
