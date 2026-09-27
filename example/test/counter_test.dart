import 'package:flutter/material.dart';
// The only change from a stock Flutter test is this import (instead of
// flutter_test): gleon re-exports flutter_test and replaces matchesGoldenFile.
import 'package:gleon/gleon.dart';
import 'package:gleon_example/main.dart';

void main() {
  // A small phone-sized surface keeps the golden PNGs small.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  testWidgets('increments the counter', (tester) async {
    await tester.pumpWidget(const CounterApp());
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('increment')));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('matches the initial golden', (tester) async {
    await tester.pumpWidget(const CounterApp());

    await expectLater(
      find.byType(CounterApp),
      matchesGoldenFile('goldens/counter_initial.png'),
    );
  });

  testWidgets('matches the golden after three taps', (tester) async {
    await tester.pumpWidget(const CounterApp());
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('increment')));
    }
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CounterApp),
      // Shows ignoreRegions (golden PNG pixels): the FAB corner is excluded.
      matchesGoldenFile(
        'goldens/counter_three_taps.png',
        ignoreRegions: [const Rect.fromLTWH(280, 560, 80, 80)],
      ),
    );
  });
}
