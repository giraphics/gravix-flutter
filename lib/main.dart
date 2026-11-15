import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'launch.dart';
import 'panels/cloud_panel.dart';
import 'panels/hierarchy_panel.dart';
import 'panels/terrain_panel.dart';
import 'panels/traffic_panel.dart';
import 'worlds/platform_backend.dart';
import 'worlds/world_backend.dart';

void main() {
  runApp(GravixApp(
    createBackend: createWorldBackend,
    // The URL flags only exist on the web; native builds start with defaults.
    launch: kIsWeb ? LaunchOptions.fromUri(Uri.base) : const LaunchOptions(),
  ));
}

class GravixApp extends StatelessWidget {
  const GravixApp({super.key, required this.createBackend, required this.launch});

  final WorldBackendFactory createBackend;
  final LaunchOptions launch;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gravix-flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6EA8FE),
          brightness: Brightness.dark,
          surface: const Color(0xFF0B0D12),
        ),
        cardTheme: const CardThemeData(color: Color(0xFF16181F)),
      ),
      home: WorldsPage(createBackend: createBackend, initialLaunch: launch),
    );
  }
}

class WorldsPage extends StatefulWidget {
  const WorldsPage({super.key, required this.createBackend, required this.initialLaunch});

  final WorldBackendFactory createBackend;
  final LaunchOptions initialLaunch;

  @override
  State<WorldsPage> createState() => _WorldsPageState();
}

class _WorldsPageState extends State<WorldsPage> {
  late LaunchOptions _launch = widget.initialLaunch;

  /// gravix-quasar's `.panel-grid`: `repeat(auto-fit, minmax(380px, 1fr))`.
  static const _minCardWidth = 380.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Changing a launch flag rebuilds every world from scratch, like reloading
    // the page with a different query string.
    final key = ValueKey(_launch);
    final panels = [
      TerrainPanel(key: key, launch: _launch, createBackend: widget.createBackend),
      CloudPanel(key: key, launch: _launch, createBackend: widget.createBackend),
      HierarchyPanel(key: key, launch: _launch, createBackend: widget.createBackend),
      TrafficPanel(key: key, launch: _launch, createBackend: widget.createBackend),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('gravix-flutter'),
        actions: [_LaunchMenu(launch: _launch, onChanged: (l) => setState(() => _launch = l))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Four worlds, one npm package: terrain, a Lorenz attractor or '
                'bouncing box, a parent/child hierarchy, and live traffic from '
                'gravix-sim-backend. Drag a world to orbit. '
                '${kIsWeb ? 'URL flags ?backend=webgl, ?failDevice=1, ?points=N and ?sim=ws://host:8081, or ' : 'Launch flags: '}'
                'the tune menu.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(_gap),
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = ((width + _gap) / (_minCardWidth + _gap)).floor().clamp(1, 3);
          final cardWidth = (width - _gap * (columns - 1)) / columns;
          return Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [for (final p in panels) SizedBox(width: cardWidth, child: p)],
          );
        }),
      ),
    );
  }
}

/// The launch flags as a menu: Force WebGL2, Fail WebGPU device, point count.
class _LaunchMenu extends StatelessWidget {
  const _LaunchMenu({required this.launch, required this.onChanged});

  final LaunchOptions launch;
  final ValueChanged<LaunchOptions> onChanged;

  static const _pointChoices = [10000, 100000, 300000, 1000000];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LaunchOptions>(
      tooltip: 'Launch options',
      icon: const Icon(Icons.tune),
      onSelected: onChanged,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: launch.copyWith(forceWebGL: !launch.forceWebGL),
          checked: launch.forceWebGL,
          child: const Text('Force WebGL2'),
        ),
        CheckedPopupMenuItem(
          value: launch.copyWith(failDevice: !launch.failDevice),
          checked: launch.failDevice,
          child: const Text('Fail WebGPU device'),
        ),
        const PopupMenuDivider(),
        for (final n in _pointChoices)
          CheckedPopupMenuItem(
            value: launch.copyWith(points: n),
            checked: launch.points == n,
            child: Text('${n ~/ 1000}k points'),
          ),
      ],
    );
  }
}
