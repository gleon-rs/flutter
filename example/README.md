# gleon example

The Flutter counter app, with tests that use `package:gleon/gleon.dart` instead of `flutter_test`:
see `test/counter_test.dart` (suite-wide setup in `test/flutter_test_config.dart`). The goldens are
recorded on an Apple silicon Mac with the app's real fonts and compared exactly by the rule in
`.gleon/gleon.yaml`, whose `fallback_platform: macos-aarch64` names that platform (see "Real text"
in the package README for how other platforms compare them).

The only change from a stock Flutter golden test is the import:

```dart
import 'package:gleon/gleon.dart'; // instead of package:flutter_test/flutter_test.dart

void main() {
  testWidgets('matches the initial golden', (tester) async {
    await tester.pumpWidget(const Main());

    await expectLater(
      find.byType(Main),
      matchesGoldenFile('goldens/counter_initial.png'),
    );
  });
}
```

A tolerance for one golden goes on the call, e.g.
`matchesGoldenFile('goldens/chart.png', tolerance: GoldenTolerance.ssim())`; tolerances for many
goldens go into `.gleon/gleon.yaml`.

```sh
flutter test                   # compares the goldens
flutter test --update-goldens  # records the goldens (stamped with this platform)
flutter run -d macos           # or linux / windows
```
