// The web build talks to the bundle directly; everything else hosts it in a
// WebView. Exports `createWorldBackend`, a WorldBackendFactory.
export 'world_backend_native.dart'
    if (dart.library.js_interop) 'world_backend_web.dart';
