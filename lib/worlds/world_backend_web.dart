import 'dart:convert';
import 'dart:js_interop';

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import '../launch.dart';
import 'world_backend.dart';

/// `window.GravixWorlds`, from assets/www/gravix_worlds.js (loaded by
/// web/index.html before Flutter starts).
@JS('GravixWorlds')
external _GravixWorldsJS? get _worlds;

extension type _GravixWorldsJS._(JSObject _) implements JSObject {
  external JSPromise<JSString> mount(
      String kind, web.HTMLElement host, String launchJson);
  external JSString state(String kind);
  external void invoke(String kind, String action, String argsJson);
  external void dispose(String kind);
}

WorldBackend createWorldBackend(WorldKind kind, LaunchOptions launch) =>
    _WebWorldBackend(kind, launch);

/// All three worlds share the page: each gets a <div> via HtmlElementView.
class _WebWorldBackend implements WorldBackend {
  _WebWorldBackend(this.kind, this.launch) {
    view = HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: _onElementCreated,
    );
  }

  final WorldKind kind;
  final LaunchOptions launch;
  String? _error;

  @override
  late final Widget view;

  void _onElementCreated(Object element) {
    final host = (element as JSObject) as web.HTMLElement;
    host.style
      ..width = '100%'
      ..height = '100%';
    final worlds = _worlds;
    if (worlds == null) {
      _error = 'gravix_worlds.js is missing: run `npm run build` in web_src/';
      return;
    }
    // Failures land in GravixWorlds.state().error; just don't leave the
    // promise rejection unhandled.
    worlds.mount(kind.name, host, launch.toJson()).toDart.ignore();
  }

  @override
  Future<Map<String, Object?>> readState() async {
    if (_error != null) return {'mounted': false, 'error': _error};
    final worlds = _worlds;
    if (worlds == null) return const {};
    return jsonDecode(worlds.state(kind.name).toDart) as Map<String, Object?>;
  }

  @override
  void invoke(String action, [List<Object?> args = const []]) =>
      _worlds?.invoke(kind.name, action, jsonEncode(args));

  @override
  void dispose() => _worlds?.dispose(kind.name);
}
