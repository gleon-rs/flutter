import 'dart:async';

import 'package:gleon/gleon.dart';

/// Suite-wide gleon defaults: tolerate rendering noise between machines
/// (anti-aliasing, sub-pixel geometry) while still catching real changes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  gleonGoldenDefaults = const GleonGoldenConfig(mode: GoldenMode.ssim);
  await testMain();
}
