/// Drop-in replacement for Flutter's `matchesGoldenFile` with tolerance,
/// SSIM and ignore regions, powered by the gleon comparison engine.
///
/// Replace `import 'package:flutter_test/flutter_test.dart';` with
/// `import 'package:gleon/gleon.dart';` — this library re-exports everything
/// from `flutter_test` except its `matchesGoldenFile`, which is replaced by
/// the gleon version. If a file must keep both imports, use
/// `import 'package:flutter_test/flutter_test.dart' hide matchesGoldenFile;`.
///
/// Alchemist hands its widgets to gleon's matcher through
/// `package:gleon/alchemist.dart`, real text included. Other golden harnesses
/// that call `flutter_test`'s own `matchesGoldenFile` (golden_toolkit, …) get
/// the same engine through `GleonFileComparator`, installed once in
/// `test/flutter_test_config.dart`.
library;

export 'package:flutter_test/flutter_test.dart' hide matchesGoldenFile;

export 'src/core/compare/golden_tolerance.dart'
    show ExactTolerance, GoldenTolerance, PixelTolerance, SsimTolerance;
export 'src/flutter/app_fonts.dart' show loadAppFonts;
export 'src/flutter/gleon_file_comparator.dart' show GleonFileComparator;
export 'src/flutter/match_golden_file.dart' show matchesGoldenFile;
