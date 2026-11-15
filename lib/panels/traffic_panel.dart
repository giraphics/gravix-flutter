import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../launch.dart';
import '../worlds/world_backend.dart';
import 'world_card.dart';

/// A live view of a gravix-sim-backend run: roads as lines, one point per
/// vehicle, streamed over WebSocket from the Rust simulator.
///
/// The connection lives in the JS world (`web_src/src/traffic.ts`); this panel
/// only picks the address, the scenario and the vehicle count, and sends
/// `connect`, `disconnect` and `setPaused`.
class TrafficPanel extends StatefulWidget {
  const TrafficPanel({super.key, required this.launch, required this.createBackend});

  final LaunchOptions launch;
  final WorldBackendFactory createBackend;

  /// The simulator's own scenarios, from `GET /scenarios`.
  static const scenarios = ['grid-small', 'grid-city', 'grid-stress'];

  static const vehicleChoices = [20, 200, 1000, 5000];

  /// Where a simulator started with `cargo run -- serve` is reachable from
  /// here. The Android emulator reaches the host's localhost as 10.0.2.2.
  static String get defaultAddress =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'ws://10.0.2.2:8081'
          : 'ws://127.0.0.1:8081';

  @override
  State<TrafficPanel> createState() => _TrafficPanelState();
}

class _TrafficPanelState extends State<TrafficPanel> {
  late final _address = TextEditingController(
    text: widget.launch.simUrl.isEmpty ? TrafficPanel.defaultAddress : widget.launch.simUrl,
  );
  String _scenario = 'grid-city';
  int _vehicles = 200;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WorldCard(
      kind: WorldKind.traffic,
      launch: widget.launch,
      createBackend: widget.createBackend,
      extraStats: _trafficStats,
      controls: (context, s, invoke) {
        final status = s['status'] as String? ?? 'disconnected';
        final live = status == 'connected' || status == 'connecting';
        final message = s['message'] as String? ?? '';
        return Column(children: [
          ControlRow(
            label: 'Simulator',
            child: SizedBox(
              width: 230,
              child: TextField(
                controller: _address,
                enabled: !live,
                decoration: const InputDecoration(isDense: true, hintText: 'ws://host:8081'),
                keyboardType: TextInputType.url,
                onSubmitted: (_) => _connect(invoke),
              ),
            ),
          ),
          ControlRow(
            label: 'Scenario',
            child: DropdownButton<String>(
              value: _scenario,
              isDense: true,
              items: [
                for (final name in TrafficPanel.scenarios)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: live
                  ? null
                  : (v) {
                      if (v != null) setState(() => _scenario = v);
                    },
            ),
          ),
          ControlRow(
            label: 'Vehicles',
            child: DropdownButton<int>(
              value: _vehicles,
              isDense: true,
              items: [
                for (final n in TrafficPanel.vehicleChoices)
                  DropdownMenuItem(value: n, child: Text(grouped(n))),
              ],
              onChanged: live
                  ? null
                  : (v) {
                      if (v != null) setState(() => _vehicles = v);
                    },
            ),
          ),
          ControlRow(
            label: 'Paused',
            child: Switch(
              value: s['paused'] as bool? ?? false,
              onChanged: status == 'connected' ? (v) => invoke('setPaused', [v]) : null,
            ),
          ),
          ControlRow(
            label: message.isEmpty ? 'Status: $status' : 'Status: $status — $message',
            child: live
                ? OutlinedButton(
                    onPressed: () => invoke('disconnect'),
                    child: const Text('Disconnect'),
                  )
                : FilledButton(
                    onPressed: () => _connect(invoke),
                    child: const Text('Connect'),
                  ),
          ),
        ]);
      },
    );
  }

  void _connect(void Function(String action, [List<Object?> args]) invoke) {
    invoke('connect', [_address.text.trim(), _scenario, _vehicles, 1]);
  }
}

/// `sim 20 Hz · tick 123 · 200 vehicles · latency 0.2 ms`, once connected.
String _trafficStats(Map<String, Object?> s) {
  if (s['status'] != 'connected') return 'sim ${s['status'] ?? 'disconnected'}';
  final hz = (s['streamFps'] as num? ?? 0).toStringAsFixed(1);
  final latency = (s['latencyMs'] as num? ?? 0).toStringAsFixed(1);
  return 'sim $hz Hz · tick ${grouped(s['tick'])} · '
      '${grouped(s['vehicles'])} vehicles · latency $latency ms';
}
