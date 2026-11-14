import 'package:material_ui/material_ui.dart';

import '../launch.dart';

/// The three worlds, named as `GravixWorlds` knows them.
enum WorldKind { terrain, cloud, hierarchy }

/// One running gravix world, wherever it runs.
///
/// Implemented twice: [HtmlElementView] + `dart:js_interop` on the web
/// (`world_backend_web.dart`), and a WebView per world on Windows and Android
/// (`world_backend_native.dart`). The panels only use this interface, so the
/// controls are written once, and tests substitute a fake.
abstract class WorldBackend {
  /// The surface the world draws into. Build it once and reuse it.
  Widget get view;

  /// The latest `GravixWorlds.state(kind)` snapshot (`{}` until mounted).
  Future<Map<String, Object?>> readState();

  /// Forward one control change: `GravixWorlds.invoke(kind, action, args)`.
  void invoke(String action, [List<Object?> args = const []]);

  void dispose();
}

typedef WorldBackendFactory = WorldBackend Function(
  WorldKind kind,
  LaunchOptions launch,
);
