import 'package:flutter_test/flutter_test.dart';
import 'package:gravix_flutter/launch.dart';
import 'package:gravix_flutter/main.dart';
import 'package:gravix_flutter/worlds/world_backend.dart';
import 'package:material_ui/material_ui.dart';

/// Stands in for a running world: canned state, and a log of every action.
class FakeWorld implements WorldBackend {
  FakeWorld(this.kind, this.launch, this.state);

  final WorldKind kind;
  final LaunchOptions launch;
  Map<String, Object?> state;
  final calls = <String>[];
  bool disposed = false;

  @override
  Widget get view => const SizedBox.expand();

  @override
  Future<Map<String, Object?>> readState() async => state;

  @override
  void invoke(String action, [List<Object?> args = const []]) =>
      calls.add('$action $args');

  @override
  void dispose() => disposed = true;
}

const _common = {
  'mounted': true, 'ready': true, 'error': null, //
  'backend': 'webgpu', 'fps': 60, 'frame': 120, 'resources': 3,
};

Map<String, Object?> _stateFor(WorldKind kind) => switch (kind) {
      WorldKind.terrain => {
          ..._common, 'visible': true, 'percent': 100, //
          'indexCount': 13824, 'drawn': 13824, 'verts': 13824,
        },
      WorldKind.cloud => {
          ..._common, 'visible': true, 'animate': true, 'demo': 'lorenz', //
          'percent': 100, 'count': 300000, 'capacity': 300000, 'verts': 300000,
          'a': 3, 'b': 1, 'r': 26.5, 'dt': 0.01, 'alpha': 1,
        },
      WorldKind.hierarchy => {
          ..._common, 'parentVisible': true, 'childVisible': true, //
          'orbit': true, 'cycles': 2, 'verts': 6,
        },
      WorldKind.traffic => {
          ..._common, 'status': 'connected', 'message': '', 'paused': false, //
          'tick': 123, 'vehicles': 200, 'roads': 1104, 'streamFps': 20.0,
          'latencyMs': 0.2, 'decodeErrors': 0, 'verts': 2408,
        },
    };

void main() {
  late List<FakeWorld> worlds;

  Future<void> pumpApp(WidgetTester tester, {String trafficStatus = 'connected'}) async {
    worlds = [];
    // Tall enough that all four cards are on screen, so taps reach them.
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    await tester.pumpWidget(GravixApp(
      launch: const LaunchOptions(),
      createBackend: (kind, launch) {
        final state = kind == WorldKind.traffic
            ? {..._stateFor(kind), 'status': trafficStatus}
            : _stateFor(kind);
        final w = FakeWorld(kind, launch, state);
        worlds.add(w);
        return w;
      },
    ));
    // Let the 250 ms poll deliver the first state.
    await tester.pump(const Duration(milliseconds: 300));
  }

  FakeWorld world(WorldKind kind) => worlds.lastWhere((w) => w.kind == kind);

  testWidgets('shows each world and its stats', (tester) async {
    await pumpApp(tester);

    expect(find.text('gravix-flutter'), findsOneWidget);
    expect(find.text('Draw count 13,824 / 13,824'), findsOneWidget);
    expect(find.text('Points 300,000 / 300,000'), findsOneWidget);
    expect(find.textContaining('backend webgpu · fps 60'), findsNWidgets(4));
    expect(find.textContaining('cycles 2'), findsOneWidget);
    expect(find.textContaining('sim 20.0 Hz · tick 123 · 200 vehicles'), findsOneWidget);
  });

  testWidgets('controls send actions to their own world', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Destroy / recreate'));
    await tester.tap(find.text('Reset'));
    await tester.enterText(find.widgetWithText(TextField, 'r'), '28');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(world(WorldKind.hierarchy).calls, ['recycle []']);
    expect(world(WorldKind.cloud).calls, ['reset []', 'setParam [r, 28.0]']);
    expect(world(WorldKind.terrain).calls, isEmpty);
    expect(world(WorldKind.traffic).calls, isEmpty);
  });

  testWidgets('the traffic card pauses and disconnects its run', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await tester.pump();

    expect(world(WorldKind.traffic).calls, ['disconnect []']);
  });

  testWidgets('the traffic card connects with the chosen address', (tester) async {
    await pumpApp(tester, trafficStatus: 'disconnected');

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();

    expect(world(WorldKind.traffic).calls,
        ['connect [ws://127.0.0.1:8081, grid-city, 200, 1]']);
  });

  testWidgets('changing a launch flag rebuilds every world', (tester) async {
    await pumpApp(tester);
    final first = List.of(worlds);

    await tester.tap(find.byTooltip('Launch options'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<LaunchOptions>, 'Force WebGL2'));
    await tester.pumpAndSettle();

    expect(first.every((w) => w.disposed), isTrue);
    expect(worlds.length, 8);
    expect(worlds.skip(4).every((w) => w.launch.forceWebGL), isTrue);
  });

  test('reads the URL flags before and after the hash', () {
    final l = LaunchOptions.fromUri(
        Uri.parse('https://x/gravix-flutter/?backend=webgl#/?points=5000&failDevice=1'));
    expect(l.forceWebGL, isTrue);
    expect(l.failDevice, isTrue);
    expect(l.points, 5000);
    expect(LaunchOptions.fromUri(Uri.parse('https://x/?points=-3')).points,
        LaunchOptions.defaultPoints);
  });

  test('reads the simulator address from ?sim=', () {
    expect(LaunchOptions.fromUri(Uri.parse('https://x/?sim=ws://h:8081')).simUrl, 'ws://h:8081');
    expect(const LaunchOptions().simUrl, isEmpty);
    expect(const LaunchOptions(simUrl: 'ws://a').toJson(), contains('"sim":"ws://a"'));
  });
}
