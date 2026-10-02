import 'dart:async';
import 'dart:ui';

import 'package:gleon/gleon.dart';

/// Suite-wide setup: the app's real fonts instead of Flutter's test font
/// (whose glyphs are all the same box), and a small phone-sized surface that
/// keeps the golden PNGs small. The golden tolerance is not set here: it
/// comes from the rule in `.gleon/gleon.yaml`.
// ignore: prefer-async-callback, the signature flutter_test looks for.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  setUp(_usePhoneSurface);
  await testMain();
}

void _usePhoneSurface() {
  final view =
      TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView;
  if (view == null) return;
  view
    ..physicalSize = const Size(360, 640)
    ..devicePixelRatio = 1;
  addTearDown(view.reset);
}
