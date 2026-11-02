import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adfree_youtube/startup.dart';

void main() {
  testWidgets('paints loading before initialization and opens on success', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: BrowserStartup(
      initialize: () => ready.future,
      child: const Text('Music screen'),
    )));
    expect(find.text('Starting the music browser…'), findsOneWidget);
    expect(find.text('Music screen'), findsNothing);
    ready.complete();
    await tester.pump();
    expect(find.text('Music screen'), findsOneWidget);
  });

  testWidgets('a hung initializer shows recovery after timeout', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: BrowserStartup(
      initialize: () => ready.future,
      timeout: const Duration(seconds: 1),
      child: const Text('Music screen'),
    )));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('The music browser could not start.'), findsOneWidget);
    ready.complete();
    await tester.pump();
    expect(find.text('Music screen'), findsNothing);
  });

  testWidgets('native startup errors are visible', (tester) async {
    await tester.pumpWidget(MaterialApp(home: BrowserStartup(
      initialize: () async => throw StateError('Missing runtime'),
      child: const Text('Music screen'),
    )));
    await tester.pump();
    expect(find.textContaining('Missing runtime'), findsOneWidget);
    expect(find.text('Music screen'), findsNothing);
  });
}
