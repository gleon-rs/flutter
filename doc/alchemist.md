# gleon with alchemist

[alchemist](https://pub.dev/packages/alchemist) ends every golden test with one assertion that can
be replaced. Replaced with gleon's, every alchemist golden with real text takes the best path of
gleon's matcher (the widget with the boxes of its text, no PNG encoded to compare), and neither
package depends on the other. This page is the whole integration; the README's
[Golden harnesses](../README.md#golden-harnesses) section covers every other harness through
`GleonFileComparator`.

When alchemist obscures text (`obscureText`), it passes an
image of blocks instead of the widget, so gleon cannot compare that text as text. The setup of
the example app's `test/flutter_test_config.dart`, which CI compiles and runs:

```dart
import 'dart:async';

import 'package:alchemist/alchemist.dart'
    show AlchemistConfig, CiGoldensConfig, PlatformGoldensConfig;
// Until alchemist exports it (Betterment/alchemist#188).
// The implementation_imports lint checks only the files under lib, not tests.
import 'package:alchemist/src/golden_test_adapter.dart' show goldenFileExpectationFn;
import 'package:gleon/alchemist.dart';
import 'package:gleon/gleon.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // First: alchemist loads the fonts again before each golden test, and the
  // faces loaded first stay.
  await loadAppFonts();
  goldenFileExpectationFn = gleonAlchemistExpectation();
  await AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      // One set of goldens with real text, which gleon compares on every OS.
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      ciGoldensConfig: CiGoldensConfig(
        obscureText: false,
        filePathResolver: _goldenPath,
      ),
    ),
    run: testMain,
  );
}

// Beside the other goldens: they are compared everywhere, not only on CI.
String _goldenPath(String fileName, String environmentName) => 'goldens/$fileName.png';
```

- `gleonAlchemistExpectation(tolerance:, ignoreRegions:, textTolerance:)` applies to every
  alchemist golden (the hook is global); left out, the golden's `.gleon/gleon.yaml` rule applies.
- With `obscureText` (alchemist's default for CI goldens), alchemist passes an image of blocked
  text, compared like PNG bytes without text boxes (the best-effort path of the README's
  [Golden harnesses](../README.md#golden-harnesses)); a failure then says how to compare real text
  (`shouldHintObscuredText: false` silences that). After switching `obscureText`, record the
  goldens again (`--update-goldens`): blocks and glyphs never match.
- Do not install `GleonFileComparator` as well: alchemist refuses a `diffThreshold` above 0 with
  any comparator but Flutter's own (`UnsupportedError` before comparing), and the adapter needs
  none.
- alchemist's `diffThreshold` does not apply, and a failure says so: set a tolerance instead. Its
  `forceUpdateGoldenFiles` writes like `--update-goldens` (see
  [Recording goldens on any platform](../README.md#recording-goldens-on-any-platform)).
- The example app runs this setup (`example/test/counter_page_test.dart`, with alchemist's runner
  for obscured text, `diffThreshold` and forced updates). For its passing golden (480x351 pixels,
  two scenarios, real fonts, text compared exactly) gleon's assertion takes 0.86 ms instead of
  alchemist's 4.46 ms (macOS arm64, `example/benchmark/`).
