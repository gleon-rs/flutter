# gleon (Flutter)

Drop-in replacement for Flutter's `matchesGoldenFile` with **tolerance**, **SSIM** and
**ignore regions**, powered by the gleon Rust comparison engine (the same engine as the
[gleon CLI](https://github.com/gleon-rs/gleon)).

> **Status: proof of concept (v0).** Host `flutter test` on macOS (arm64/x64) and Linux x64.
> No Rust toolchain or network access is needed: the package ships prebuilt, checksum-verified native libraries.

## Install

```yaml
dev_dependencies:
  gleon:
    git:
      url: https://github.com/gleon-rs/gleon_flutter.git
      ref: <commit-or-branch>
```

The Dart build hook picks the prebuilt library for the test host from `native/`, verifies its
SHA-256 and bundles it. Overrides, if ever needed:

```yaml
hooks:
  user_defines:
    gleon:
      ffi_path: path/to/libgleon_ffi.dylib # use a specific library
      # gleon_repo: ../gleon               # contributors: build from a gleon checkout
```

## Migrate

Replace one import — everything else from `flutter_test` stays available:

```diff
-import 'package:flutter_test/flutter_test.dart';
+import 'package:gleon/gleon.dart';
```

Without extra parameters the behavior is identical to Flutter: exact comparison, goldens
resolved relative to the test file, `flutter test --update-goldens` rewrites them, nothing is
written when tests pass. If a file must keep both imports, add
`hide matchesGoldenFile` to the `flutter_test` import.

## Tolerance

```dart
// Up to 0.5% of pixels may differ.
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile('goldens/my_widget.png', mode: GoldenMode.pixel, threshold: 0.005),
);

// Tolerates rendering noise (anti-aliasing, sub-pixel geometry, color drift),
// still catches changed/missing content, color and alpha changes, blur.
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile('goldens/my_widget.png', mode: GoldenMode.ssim),
);

// Ignore a dynamic region (pixels of the golden PNG, origin top-left).
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile(
    'goldens/my_widget.png',
    ignoreRegions: [const Rect.fromLTWH(0, 0, 400, 80)],
  ),
);
```

Suite-wide defaults, e.g. in `test/flutter_test_config.dart`:

```dart
import 'dart:async';

import 'package:gleon/gleon.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  gleonGoldenDefaults = const GleonGoldenConfig(mode: GoldenMode.ssim);
  await testMain();
}
```

| Parameter        | Applies to | Meaning                                                               |
| ---------------- | ---------- | --------------------------------------------------------------------- |
| `key`, `version` | all        | Same as Flutter.                                                      |
| `mode`           | all        | `exact` (default), `pixel`, `ssim`.                                   |
| `threshold`      | `pixel`    | Max fraction of differing pixels, 0.0–1.0 (default 0.01).             |
| `minSimilarity`  | `ssim`     | Min local SSIM of every neighborhood, 0.0–1.0 (default 0.8).          |
| `colorTolerance` | `ssim`     | Tolerated deviation beyond the local 3x3 envelope, 0–255 (default 8). |
| `ignoreRegions`  | all        | Rectangles excluded from the comparison.                              |

Passing a parameter that does not apply to the mode, or an out-of-range value, throws an
`ArgumentError` instead of being silently ignored.

On failure the test message contains the metric and the thresholds, and
`failures/<name>_masterImage.png`, `_testImage.png` and `_gleonDiff.png` are written next to the
test (like Flutter's own failure output).

## How `ssim` decides

Two gates, both computed only around the pixels that actually differ:

1. **Envelope gate** (full resolution): every pixel of one image must lie within the value range
   of the other image's 3x3 neighborhood (premultiplied RGBA, so alpha counts), widened by
   `colorTolerance` plus a share of the local contrast. Re-rasterization and sub-pixel shifts only
   produce values between neighbors; new content, color and alpha changes don't. Unexplained
   pixels fail as regions of 3+ pixels or with a strong deviation.
2. **Structural gate** (half resolution, as in MS-SSIM): the _minimum_ local SSIM (11x11 Gaussian
   window) must reach `minSimilarity`, catching structural loss such as blur. The minimum, not the
   mean, so a small change on a large golden is not averaged away.

The defaults are calibrated on a corpus of benign rendering noise vs. regressions in
`gleon-engine/tests/ssim_corpus.rs` in the gleon repository; off-the-shelf crates (`image-compare`, pixelmatch/`dify`,
`butteraugli`) could not separate that corpus with any threshold.

## Known PoC limitations

- `ssim` fails when glyphs move by half a pixel or more — typical of different operating
  systems' font engines. Keep per-platform goldens (the gleon CLI manages those for you).
- `ssim` can pass a low-contrast color change of a one-pixel line. Use `exact`/`pixel` where every
  pixel matters.
- Only Flutter's default `LocalFileComparator` is supported as the underlying golden store.
- Web (`--platform chrome`), Windows and on-device tests are not supported yet.

## Maintainers

The native code (`gleon-engine`, `gleon-ffi`) lives in the
[gleon repository](https://github.com/gleon-rs/gleon). After changing it, rebuild the prebuilt
libraries from a gleon checkout (macOS host, `brew install zig cargo-zigbuild` for the Linux
cross-link):

```sh
GLEON_REPO=../gleon tool/build_native.sh
```

`test/native_manifest_test.dart` fails if the manifest's ABI version or checksums are stale.
