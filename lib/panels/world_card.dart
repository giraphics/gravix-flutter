import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../launch.dart';
import '../worlds/world_backend.dart';

/// Builds a panel's controls from the latest state.
typedef ControlsBuilder = Widget Function(
  BuildContext context,
  Map<String, Object?> state,
  void Function(String action, [List<Object?> args]) invoke,
);

/// A card with one gravix world on top and its controls underneath: the shape
/// of each gravix-quasar panel (`q-card` + `canvas.gravix-canvas` + controls +
/// the monospace stats line).
class WorldCard extends StatefulWidget {
  const WorldCard({
    super.key,
    required this.kind,
    required this.launch,
    required this.createBackend,
    required this.controls,
    this.extraStats,
  });

  final WorldKind kind;
  final LaunchOptions launch;
  final WorldBackendFactory createBackend;
  final ControlsBuilder controls;

  /// Appended to the stats line, e.g. `cycles 3`.
  final String Function(Map<String, Object?> state)? extraStats;

  /// gravix-quasar's canvas height.
  static const viewHeight = 320.0;

  @override
  State<WorldCard> createState() => _WorldCardState();
}

class _WorldCardState extends State<WorldCard> {
  /// gravix-quasar refreshes its stats line every 250 ms.
  static const _pollInterval = Duration(milliseconds: 250);

  late final WorldBackend _backend = widget.createBackend(widget.kind, widget.launch);
  Timer? _poll;
  bool _polling = false;
  Map<String, Object?> _state = const {};

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_polling) return; // a slow WebView must not queue up reads
    _polling = true;
    try {
      final next = await _backend.readState();
      if (mounted) setState(() => _state = next);
    } finally {
      _polling = false;
    }
  }

  void _invoke(String action, [List<Object?> args = const []]) {
    _backend.invoke(action, args);
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _backend.dispose();
    super.dispose();
  }

  String _statsLine() {
    final s = _state;
    final error = s['error'];
    if (error != null) return 'error: $error';
    if (s['ready'] != true) return 'starting…';
    String n(Object? v) => _grouped((v as num?)?.round() ?? 0);
    final extra = widget.extraStats?.call(s);
    return [
      'backend ${s['backend']}',
      'fps ${n(s['fps'])}',
      'frame ${n(s['frame'])}',
      'verts ${n(s['verts'])}',
      'resources ${n(s['resources'])}',
      ?extra,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: WorldCard.viewHeight,
            child: ColoredBox(color: Colors.black, child: _backend.view),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.controls(context, _state, _invoke),
                const SizedBox(height: 8),
                Text(
                  _statsLine(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `toLocaleString()` for integers: 300000 -> 300,000.
String _grouped(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

String grouped(Object? value) => _grouped((value as num?)?.round() ?? 0);

/// A label on the left, a control on the right: gravix-quasar's control row.
class ControlRow extends StatelessWidget {
  const ControlRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          child,
        ],
      ),
    );
  }
}

/// A percent slider that follows the world's state but moves immediately while
/// dragged, instead of waiting for the next poll.
class PercentSlider extends StatefulWidget {
  const PercentSlider({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<PercentSlider> createState() => _PercentSliderState();
}

class _PercentSliderState extends State<PercentSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Slider(
        value: (_dragging ?? widget.value).clamp(0, 100),
        max: 100,
        onChanged: (v) {
          setState(() => _dragging = v);
          widget.onChanged(v);
        },
        onChangeEnd: (_) => setState(() => _dragging = null),
      ),
    );
  }
}
