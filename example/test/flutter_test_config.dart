import 'dart:async';

import 'package:gleon/gleon.dart';

/// Suite-wide gleon defaults: tolerate rendering noise between machines
/// (anti-aliasing, sub-pixel geometry) while still catching real changes.
///
/// The goldens are recorded on macOS. Other operating systems rasterize text
/// differently (measured on Linux x64: min local SSIM 0.754, color excess 32.5
/// on the text line), so the tolerances are loosened well past that for now.
/// An 11px change of the progress bar still fails with these settings.
/// Temporary until text-aware comparison lands; per-platform goldens are the
/// alternative.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  gleonGoldenDefaults = const GleonGoldenConfig(
    mode: GoldenMode.ssim,
    minSimilarity: 0.6,
    colorTolerance: 64,
  );
  await testMain();
}
