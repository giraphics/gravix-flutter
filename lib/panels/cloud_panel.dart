import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../launch.dart';
import '../worlds/world_backend.dart';
import 'world_card.dart';

/// gravix-quasar's PointCloudPanel.vue: a point cloud (300,000 by default)
/// running either a Lorenz attractor or the engine's bouncing-box simulation.
class CloudPanel extends StatelessWidget {
  const CloudPanel({super.key, required this.launch, required this.createBackend});

  final LaunchOptions launch;
  final WorldBackendFactory createBackend;

  @override
  Widget build(BuildContext context) {
    return WorldCard(
      kind: WorldKind.cloud,
      launch: launch,
      createBackend: createBackend,
      controls: (context, s, invoke) {
        final demo = s['demo'] as String? ?? 'lorenz';
        final capacity = s['capacity'] as num? ?? 0;
        return Column(children: [
          ControlRow(
            label: 'Visible',
            child: Switch(
              value: s['visible'] as bool? ?? true,
              onChanged: (v) => invoke('setVisible', [v]),
            ),
          ),
          ControlRow(
            label: 'Demo',
            child: DropdownButton<String>(
              value: demo,
              isDense: true,
              items: const [
                DropdownMenuItem(value: 'lorenz', child: Text('Lorenz attractor')),
                DropdownMenuItem(value: 'bounce', child: Text('Bouncing box')),
              ],
              onChanged: (v) {
                if (v != null) invoke('setDemo', [v]);
              },
            ),
          ),
          ControlRow(
            label: 'Points ${grouped(s['count'])} / '
                '${capacity == 0 ? '—' : grouped(capacity)}',
            child: PercentSlider(
              value: (s['percent'] as num? ?? 100).toDouble(),
              onChanged: (v) => invoke('setPercent', [v]),
            ),
          ),
          if (demo == 'lorenz' && s['ready'] == true)
            _LorenzParams(state: s, invoke: invoke),
          ControlRow(
            label: 'Animate',
            child: Switch(
              value: s['animate'] as bool? ?? true,
              onChanged: (v) => invoke('setAnimate', [v]),
            ),
          ),
        ]);
      },
    );
  }
}

/// a, b, r, dt and α as number fields, plus Reset: the Vue panel's `.params`
/// grid. A value applies when the field is submitted or loses focus.
class _LorenzParams extends StatelessWidget {
  const _LorenzParams({required this.state, required this.invoke});

  final Map<String, Object?> state;
  final void Function(String action, [List<Object?> args]) invoke;

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label) => _ParamField(
          label: label,
          initial: (state[key] as num? ?? 0).toDouble(),
          onSubmit: (v) => invoke('setParam', [key, v]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 10,
        children: [
          field('a', 'a'),
          field('b', 'b'),
          field('r', 'r'),
          field('dt', 'dt'),
          field('alpha', 'α'),
          Align(
            alignment: Alignment.bottomLeft,
            child: OutlinedButton(
              onPressed: () => invoke('reset'),
              child: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamField extends StatefulWidget {
  const _ParamField({required this.label, required this.initial, required this.onSubmit});

  final String label;
  final double initial;
  final ValueChanged<double> onSubmit;

  @override
  State<_ParamField> createState() => _ParamFieldState();
}

class _ParamFieldState extends State<_ParamField> {
  late final _text = TextEditingController(text: _format(widget.initial));
  final _focus = FocusNode();

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  /// Enter and then losing focus both submit; send each value once.
  late double _applied = widget.initial;

  void _submit() {
    final value = double.tryParse(_text.text);
    // Non-numbers are ignored, as the Vue fields' Number.isFinite guard did.
    if (value == null || !value.isFinite || value == _applied) return;
    _applied = value;
    widget.onSubmit(value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      focusNode: _focus,
      decoration: InputDecoration(labelText: widget.label, isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
      onSubmitted: (_) => _submit(),
    );
  }
}
