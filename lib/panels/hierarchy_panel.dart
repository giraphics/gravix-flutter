import 'package:material_ui/material_ui.dart';

import '../launch.dart';
import '../worlds/world_backend.dart';
import 'world_card.dart';

/// gravix-quasar's HierarchyPanel.vue: a parent triangle with a child attached,
/// an orbit system spinning the parent, and destroy/recreate to show entity
/// lifetime (the resource count returns to where it was).
class HierarchyPanel extends StatelessWidget {
  const HierarchyPanel({super.key, required this.launch, required this.createBackend});

  final LaunchOptions launch;
  final WorldBackendFactory createBackend;

  @override
  Widget build(BuildContext context) {
    return WorldCard(
      kind: WorldKind.hierarchy,
      launch: launch,
      createBackend: createBackend,
      extraStats: (s) => 'cycles ${s['cycles'] ?? 0}',
      controls: (context, s, invoke) => Column(children: [
        ControlRow(
          label: 'Parent visible',
          child: Switch(
            value: s['parentVisible'] as bool? ?? true,
            onChanged: (v) => invoke('setParentVisible', [v]),
          ),
        ),
        ControlRow(
          label: 'Child visible',
          child: Switch(
            value: s['childVisible'] as bool? ?? true,
            onChanged: (v) => invoke('setChildVisible', [v]),
          ),
        ),
        ControlRow(
          label: 'Orbit parent',
          child: Switch(
            value: s['orbit'] as bool? ?? true,
            onChanged: (v) => invoke('setOrbit', [v]),
          ),
        ),
        ControlRow(
          label: 'Lifetime',
          child: FilledButton(
            onPressed: s['ready'] == true ? () => invoke('recycle') : null,
            child: const Text('Destroy / recreate'),
          ),
        ),
      ]),
    );
  }
}
