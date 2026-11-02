import 'package:flutter/services.dart';

/// Connect OS transport buttons to the page player without a second audio source.
class MobileMediaControls {
  MobileMediaControls({
    required this.enabled,
    required this.onCommand,
    this.channel = const MethodChannel('mytube/background'),
  });

  final bool enabled;
  final Future<void> Function(String action, double? position) onCommand;
  final MethodChannel channel;

  void attach() {
    if (enabled) channel.setMethodCallHandler(handleCommand);
  }

  Future<void> handleCommand(MethodCall call) async {
    if (!enabled || call.method != 'mediaCommand' || call.arguments is! Map) return;
    final args = call.arguments as Map;
    final action = args['action'];
    if (!const {'play', 'pause', 'toggle', 'next', 'previous', 'seek'}.contains(action)) return;
    final position = args['position'] is num ? (args['position'] as num).toDouble() : null;
    if (action == 'seek' && (position == null || !position.isFinite || position < 0)) return;
    await onCommand(action as String, position);
  }

  Future<void> update(Map<String, dynamic> state) async {
    if (enabled) await channel.invokeMethod<void>('updateMedia', state);
  }

  Future<void> dispose() async {
    if (!enabled) return;
    channel.setMethodCallHandler(null);
    await channel.invokeMethod<void>('clearMedia');
  }
}
