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

export 'src/comparator.dart' show GleonGoldenComparator;
export 'src/config.dart'
    show GleonGoldenConfig, GoldenMode, gleonGoldenDefaults;
export 'src/matcher.dart' show GleonMatchesGoldenFile, matchesGoldenFile;
