import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart' as android;
import 'package:webview_windows/webview_windows.dart' as win;

import '../launch.dart';
import 'world_backend.dart';

/// Windows and Android: each world runs in its own WebView, loading
/// assets/www/world.html (which loads gravix_worlds.js), the way Electron and
/// Capacitor host gravix-quasar.
WorldBackend createWorldBackend(WorldKind kind, LaunchOptions launch) {
  if (Platform.isWindows) return _WindowsWorldBackend(kind, launch);
  if (Platform.isAndroid) return _AndroidWorldBackend(kind, launch);
  return _UnsupportedWorldBackend();
}

/// JavaScript that mounts this world into world.html's #host.
String _mountScript(WorldKind kind, LaunchOptions launch) =>
    "GravixWorlds.mount('${kind.name}', document.getElementById('host'), "
    '${jsonEncode(launch.toJson())}).catch(function () {}); true;';

String _stateScript(WorldKind kind) => "GravixWorlds.state('${kind.name}')";

String _invokeScript(WorldKind kind, String action, List<Object?> args) =>
    "GravixWorlds.invoke('${kind.name}', ${jsonEncode(action)}, "
    '${jsonEncode(jsonEncode(args))}); true;';

/// Both WebViews JSON-encode a script's return value, and state() itself
/// returns a JSON string, so unwrap strings until the map appears.
Map<String, Object?> _decodeState(Object? result) {
  var value = result;
  for (var i = 0; i < 3 && value is String; i++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return const {};
    }
  }
  return value is Map ? Map<String, Object?>.from(value) : const {};
}

// ---------------------------------------------------------------------------
// Windows: WebView2 through webview_windows.

class _WindowsWorldBackend implements WorldBackend {
  _WindowsWorldBackend(this.kind, this.launch) {
    view = ValueListenableBuilder<win.WebviewValue>(
      valueListenable: _controller,
      builder: (context, value, _) => value.isInitialized
          ? win.Webview(_controller)
          : const ColoredBox(color: Colors.black),
    );
    _ready = _start();
  }

  /// Served from the app's own asset folder under a made-up https host, so the
  /// page is a secure context (WebGPU requires one) and can load its script.
  static const _host = 'gravix.assets';

  final WorldKind kind;
  final LaunchOptions launch;
  final _controller = win.WebviewController();
  late final Future<void> _ready;
  String? _error;
  bool _disposed = false;

  @override
  late final Widget view;

  Future<void> _start() async {
    try {
      await _controller.initialize();
      if (_disposed) return;
      await _controller.setBackgroundColor(Colors.black);
      final www = [
        File(Platform.resolvedExecutable).parent.path,
        'data', 'flutter_assets', 'assets', 'www', //
      ].join(Platform.pathSeparator);
      await _controller.addVirtualHostNameMapping(
          _host, www, win.WebviewHostResourceAccessKind.allow);
      final loaded = _controller.loadingState
          .firstWhere((s) => s == win.LoadingState.navigationCompleted);
      await _controller.loadUrl('https://$_host/world.html');
      await loaded;
      if (_disposed) return;
      await _controller.executeScript(_mountScript(kind, launch));
    } catch (e) {
      _error = 'WebView2 failed to start: $e';
    }
  }

  @override
  Future<Map<String, Object?>> readState() async {
    await _ready;
    if (_error != null) return {'mounted': false, 'error': _error};
    if (_disposed) return const {};
    return _decodeState(await _controller.executeScript(_stateScript(kind)));
  }

  @override
  void invoke(String action, [List<Object?> args = const []]) {
    _ready.then((_) {
      if (!_disposed && _error == null) {
        _controller.executeScript(_invokeScript(kind, action, args));
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _ready.whenComplete(_controller.dispose);
  }
}

// ---------------------------------------------------------------------------
// Android: the system WebView through webview_flutter.

class _AndroidWorldBackend implements WorldBackend {
  _AndroidWorldBackend(this.kind, this.launch) {
    final pageLoaded = Completer<void>();
    _controller
      ..setJavaScriptMode(android.JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(android.NavigationDelegate(
        onPageFinished: (_) {
          if (!pageLoaded.isCompleted) pageLoaded.complete();
        },
      ))
      ..loadFlutterAsset('assets/www/world.html');
    _ready = pageLoaded.future.then((_) async {
      if (!_disposed) await _controller.runJavaScript(_mountScript(kind, launch));
    });
    view = android.WebViewWidget(
      controller: _controller,
      // Drags inside the card orbit the camera instead of scrolling the page.
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }

  final WorldKind kind;
  final LaunchOptions launch;
  final _controller = android.WebViewController();
  late final Future<void> _ready;
  bool _disposed = false;

  @override
  late final Widget view;

  @override
  Future<Map<String, Object?>> readState() async {
    await _ready;
    if (_disposed) return const {};
    return _decodeState(
        await _controller.runJavaScriptReturningResult(_stateScript(kind)));
  }

  @override
  void invoke(String action, [List<Object?> args = const []]) {
    _ready.then((_) {
      if (!_disposed) _controller.runJavaScript(_invokeScript(kind, action, args));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    // The WebView is released with its widget.
  }
}

// ---------------------------------------------------------------------------

class _UnsupportedWorldBackend implements WorldBackend {
  @override
  Widget get view => const Center(
      child: Text('This platform is not supported: use web, Windows or Android'));

  @override
  Future<Map<String, Object?>> readState() async =>
      {'mounted': false, 'error': 'unsupported platform'};

  @override
  void invoke(String action, [List<Object?> args = const []]) {}

  @override
  void dispose() {}
}
