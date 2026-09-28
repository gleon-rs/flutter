import 'package:flutter/material.dart';
// The only change from a stock Flutter test is this import (instead of
// flutter_test): gleon re-exports flutter_test and replaces matchesGoldenFile.
// The tolerance comes from the rule in `.gleon/gleon.yaml`.
import 'package:gleon/gleon.dart';
import 'package:gleon_example/main.dart';

void main() {
  testWidgets('increments the counter', (tester) async {
    await tester.pumpWidget(const Main());
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('increment')));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('matches the initial golden', (tester) async {
    await tester.pumpWidget(const Main());

    await expectLater(
      find.byType(Main),
      matchesGoldenFile('goldens/counter_initial.png'),
    );
  });

  testWidgets('matches the golden after three taps', (tester) async {
    await tester.pumpWidget(const Main());
    for (int i = 0; i < 3; i += 1) {
      await tester.tap(find.byKey(const ValueKey('increment')));
    }
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Main),
      // Shows ignoreRegions (golden PNG pixels): the FAB corner is excluded,
      // and the dot shorthand for an inline tolerance.
      matchesGoldenFile(
        'goldens/counter_three_taps.png',
        tolerance: const .ssim(minSimilarity: 0.6, colorTolerance: 64),
        ignoreRegions: [const Rect.fromLTWH(280, 560, 80, 80)],
      ),
    );
  });
}
