import 'dart:async';
import 'dart:ui';

import 'package:alchemist/alchemist.dart'
    show AlchemistConfig, CiGoldensConfig, PlatformGoldensConfig;
// Until alchemist exports its golden file expectation (Betterment/alchemist#188).
// The implementation_imports lint checks only the files under lib, not tests.
import 'package:alchemist/src/golden_test_adapter.dart'
    show goldenFileExpectationFn;
import 'package:gleon/alchemist.dart';
import 'package:gleon/gleon.dart';

/// Suite-wide setup: the app's real fonts instead of Flutter's test font
/// (whose glyphs are all the same box), and a small phone-sized surface that
/// keeps the golden PNGs small. The golden tolerance is not set here: it
/// comes from the rule in `.gleon/gleon.yaml`.
///
/// Alchemist's golden tests compare with gleon too: one set of goldens with
/// real text (its CI variant, text not obscured, no per-OS platform variant),
/// which gleon compares on every OS (see `fallback_platform`). After
/// switching `obscureText`, record the goldens again.
// ignore: prefer-async-callback, the signature flutter_test looks for.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  setUp(_usePhoneSurface);
  goldenFileExpectationFn = gleonAlchemistExpectation();

  await AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
      ciGoldensConfig: CiGoldensConfig(
        obscureText: false,
        filePathResolver: _goldenPath,
      ),
    ),
    run: testMain,
  );
}

/// Alchemist's goldens beside the others: gleon compares them on every OS,
/// so they are not CI goldens (alchemist's default `goldens/ci/`).
String _goldenPath(String fileName, String environmentName) =>
    'goldens/$fileName.png';

void _usePhoneSurface() {
  final view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView;
  if (view == null) return;
  view
    ..physicalSize = const Size(360, 640)
    ..devicePixelRatio = 1;
  addTearDown(view.reset);
}
