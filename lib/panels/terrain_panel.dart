import 'package:material_ui/material_ui.dart';

import '../launch.dart';
import '../worlds/world_backend.dart';
import 'world_card.dart';

/// gravix-quasar's TerrainPanel.vue: a 48×48 height-field mesh, with a
/// visibility toggle and a slider over how many of its indices are drawn.
class TerrainPanel extends StatelessWidget {
  const TerrainPanel({super.key, required this.launch, required this.createBackend});

  final LaunchOptions launch;
  final WorldBackendFactory createBackend;

  @override
  Widget build(BuildContext context) {
    return WorldCard(
      kind: WorldKind.terrain,
      launch: launch,
      createBackend: createBackend,
      controls: (context, s, invoke) {
        final indexCount = s['indexCount'] as num? ?? 0;
        return Column(children: [
          ControlRow(
            label: 'Visible',
            child: Switch(
              value: s['visible'] as bool? ?? true,
              onChanged: (v) => invoke('setVisible', [v]),
            ),
          ),
          ControlRow(
            label: 'Draw count ${grouped(s['drawn'])} / '
                '${indexCount == 0 ? '—' : grouped(indexCount)}',
            child: PercentSlider(
              value: (s['percent'] as num? ?? 100).toDouble(),
              onChanged: (v) => invoke('setPercent', [v]),
            ),
          ),
        ]);
      },
    );
  }
}
