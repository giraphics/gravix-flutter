import 'dart:convert';

/// The three launch flags gravix-quasar reads from the URL.
///
/// On the web they come from the address bar (`?backend=webgl`,
/// `?failDevice=1`, `?points=N`, before or after the `#`). On Windows and
/// Android there is no address bar, so the same values are set from the app
/// bar's launch menu.
class LaunchOptions {
  const LaunchOptions({
    this.forceWebGL = false,
    this.failDevice = false,
    this.points = defaultPoints,
  });

  static const defaultPoints = 300000;

  /// Read from a URL the way gravix-quasar's `readLaunchOptions` does: query
  /// before the hash wins, query after the hash fills in what's missing.
  factory LaunchOptions.fromUri(Uri uri) {
    final params = <String, String>{...uri.queryParameters};
    final hashQuery = uri.fragment.indexOf('?');
    if (hashQuery >= 0) {
      final fromHash = Uri.splitQueryString(uri.fragment.substring(hashQuery + 1));
      fromHash.forEach((k, v) => params.putIfAbsent(k, () => v));
    }
    final points = int.tryParse(params['points'] ?? '');
    return LaunchOptions(
      forceWebGL: params['backend'] == 'webgl',
      failDevice: params['failDevice'] == '1',
      points: points != null && points > 0 ? points : defaultPoints,
    );
  }

  /// WebGPU when the device has it, WebGL2 otherwise; or WebGL2 only.
  final bool forceWebGL;

  /// Make WebGPU device creation fail, to exercise the WebGL2 fallback.
  final bool failDevice;

  /// Point-cloud capacity.
  final int points;

  /// What `GravixWorlds.mount` expects.
  String toJson() => jsonEncode({
        'backend': forceWebGL ? 'webgl' : 'auto',
        'failDevice': failDevice,
        'points': points,
      });

  LaunchOptions copyWith({bool? forceWebGL, bool? failDevice, int? points}) =>
      LaunchOptions(
        forceWebGL: forceWebGL ?? this.forceWebGL,
        failDevice: failDevice ?? this.failDevice,
        points: points ?? this.points,
      );

  @override
  bool operator ==(Object other) =>
      other is LaunchOptions &&
      other.forceWebGL == forceWebGL &&
      other.failDevice == failDevice &&
      other.points == points;

  @override
  int get hashCode => Object.hash(forceWebGL, failDevice, points);
}
