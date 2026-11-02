import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adfree_youtube/mobile_media_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mytube/background');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('publishes metadata and clears native controls on disposal', () async {
    final bridge = MobileMediaControls(enabled: true, onCommand: (_, __) async {});
    bridge.attach();
    await bridge.update({'trackTitle': 'Song', 'playing': true, 'position': 1200, 'duration': 90000, 'hasMedia': true});
    expect(calls.single.method, 'updateMedia');
    expect((calls.single.arguments as Map)['position'], 1200);
    await bridge.dispose();
    expect(calls.last.method, 'clearMedia');
  });

  test('explicit play/pause and seek commands route without toggling', () async {
    final actions = <String>[];
    double? seek;
    final bridge = MobileMediaControls(enabled: true, onCommand: (action, position) async {
      actions.add(action);
      seek = position;
    });
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'play'}));
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'pause'}));
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'next'}));
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'previous'}));
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'seek', 'position': 30}));
    expect(actions, ['play', 'pause', 'next', 'previous', 'seek']);
    expect(seek, 30.0);
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'seek', 'position': -1}));
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'unknown'}));
    expect(actions.length, 5);
  });

  test('desktop bridge makes no mobile native calls', () async {
    final bridge = MobileMediaControls(enabled: false, onCommand: (_, __) async { fail('Unexpected command'); });
    bridge.attach();
    await bridge.update({'hasMedia': true});
    await bridge.dispose();
    await bridge.handleCommand(const MethodCall('mediaCommand', {'action': 'play'}));
    expect(calls, isEmpty);
  });
}
