/// Drop-in replacement for Flutter's `matchesGoldenFile` with tolerance,
/// SSIM and ignore regions, powered by the gleon comparison engine.
///
/// Replace `import 'package:flutter_test/flutter_test.dart';` with
/// `import 'package:gleon/gleon.dart';` — this library re-exports everything
/// from `flutter_test` except its `matchesGoldenFile`, which is replaced by
/// the gleon version. If a file must keep both imports, use
/// `import 'package:flutter_test/flutter_test.dart' hide matchesGoldenFile;`.
library;

export 'package:flutter_test/flutter_test.dart' hide matchesGoldenFile;

export 'src/core/compare/golden_tolerance.dart'
    show
        ExactTolerance,
        GoldenTolerance,
        PixelTolerance,
        SsimTolerance,
        TextTolerance;
export 'src/flutter/app_fonts.dart' show loadAppFonts;
export 'src/flutter/match_golden_file.dart' show matchesGoldenFile;
