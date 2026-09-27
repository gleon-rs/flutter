# gleon (Flutter)

Drop-in replacement for Flutter's `matchesGoldenFile` with **tolerance**, **SSIM** and
**ignore regions**, powered by the gleon Rust comparison engine (the same engine as the
[gleon CLI](https://github.com/gleon-rs/gleon)).

> **Status: proof of concept (v0).** Host `flutter test` on macOS arm64, Linux x64/arm64
> (Ubuntu 26.04+) and Windows x64. No Rust toolchain is needed: prebuilt, checksum-verified native
> libraries are downloaded once per project.

## Install

```yaml
dev_dependencies:
  gleon:
    git:
      url: https://github.com/gleon-rs/flutter.git
      ref: v0.0.1 # a released tag: prebuilt libraries exist for tags only
```

On the first `flutter test`, the package's build hook downloads the native library for the test
host from the GitHub Release of that version, verifies it against the release's `SHA256SUMS.txt`
(releases are immutable) and caches it in `.dart_tool/hooks_runner/shared/`. Later runs, including
offline ones, reuse the cache until `flutter clean`. `HTTPS_PROXY` is honored.

Overrides (in the app's `pubspec.yaml`), e.g. for air-gapped machines:

```yaml
hooks:
  user_defines:
    gleon:
      ffi_path: path/to/libgleon_ffi.dylib # use this library file as is
      # release_url: https://mirror.example/gleon/v0.0.1/ # SHA256SUMS.txt + assets
      # gleon_repo: ../gleon               # contributors: build from a gleon checkout
```

See [`example/`](example) for a counter app whose tests use gleon.

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
- Web (`--platform chrome`) and on-device tests are not supported.

## Maintainers

The native code (`gleon-engine`, `gleon-ffi`) lives in the
[gleon repository](https://github.com/gleon-rs/gleon); `native/gleon_ref` pins the commit CI builds.
Build the library for this machine into `native/<target>/` (the hook prefers it over downloading):

```sh
dart bin/build_native.dart                 # host; --target all cross-builds on macOS
```

Use plain `dart`, not `dart run`: `dart run` executes the build hook first. Cross builds need
`cargo-zigbuild` (Linux) and `cargo-xwin` (Windows); CI builds every target natively.

Releasing: bump `version` in `pubspec.yaml` and `CHANGELOG.md`, update `native/gleon_ref` if the
engine changed, and push the tag `vX.Y.Z`. The release workflow builds and tests all targets on
their own OS, attaches the libraries and `SHA256SUMS.txt` to an immutable GitHub Release, and then
verifies the download path on every OS.
