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
      ref: v0.1.0 # a released tag: prebuilt libraries exist for tags only
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
      # release_url: https://mirror.example/gleon/v0.1.0/ # SHA256SUMS.txt + assets
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

`tolerance` takes a `GoldenTolerance`; dot shorthands keep call sites short:

```dart
// Up to 0.5% of pixels may differ.
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile(
    'goldens/my_widget.png',
    tolerance: const .pixel(maxDiffRatio: 0.005),
  ),
);

// Tolerates rendering noise (anti-aliasing, sub-pixel geometry, color drift),
// still catches changed/missing content, color and alpha changes, blur.
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile('goldens/my_widget.png', tolerance: const .ssim()),
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

| Tolerance                                              | Meaning                                                                                                                             |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `.exact()` (default)                                   | Every pixel must be identical, like Flutter.                                                                                        |
| `.pixel({maxDiffRatio = 0.01})`                        | At most this fraction (0.0–1.0) of pixels may differ.                                                                               |
| `.ssim({minSimilarity = 0.8, colorTolerance = 8})`     | Min local SSIM of every neighborhood (0.0–1.0) and tolerated deviation beyond the local 3x3 envelope (0–255); see below.            |

`ignoreRegions` (rectangles excluded from the comparison) works with every tolerance. Each
variant only has the parameters of its mode, so a setting for the wrong mode cannot be written;
out-of-range values throw an `ArgumentError` when the matcher is created.

On failure the test message contains the metric and the thresholds, and
`failures/<name>_masterImage.png`, `_testImage.png` and `_gleonDiff.png` are written next to the
test (like Flutter's own failure output).

Suite-wide tolerances per path live in `.gleon/gleon.yaml`, see below.

## Configuration with `.gleon/gleon.yaml`

Suite settings live in the [gleon CLI](https://github.com/gleon-rs/gleon)'s workspace file —
the very same file, so a project that later adopts the CLI keeps its rules. On the first
comparison the package looks for `.gleon/gleon.yaml` from the working directory (the package root
under `flutter test`) upwards, reads it once per test process, and resolves the rule of every
golden by its path relative to that directory, with the CLI's own code:

```yaml
# .gleon/gleon.yaml (create it by hand or with `gleon init`)
required_version: ">=0.1.0"

exclude: "test/goldens/experimental/**"

screenshots:
  # The first matching rule wins.
  - include: "test/goldens/**/*.png"
    mode: ssim
    diff: { min_similarity: 0.8, color_tolerance: 8 }
    masks:
      - path: "**/clock*.png"
        zones: [{ x: 0, y: 0, width: "25%", height: 40 }] # pixels or "NN%"
  - include: "test/**/*.png"
    mode: pixel
    diff: { threshold: 0.01 } # max fraction of differing pixels; 0 = exact

metrics:
  enabled: false
```

- **Priority:** the `tolerance` argument of a call beats the golden's rule, which beats exact.
  Masks of the rule are added to the call's `ignoreRegions`.
- A golden matched by `exclude` (or inside a directory the CLI never scans, such as `build/`) or
  by no rule is compared exactly, like without the file.
- Golden paths must be valid gleon test names (`[a-z0-9_.-]` segments, case-insensitive), as for
  `gleon stage`; an invalid config or name fails the test with the file path and the parser's
  message. Unknown keys are rejected.
- `required_version` is only checked for syntax here; the CLI enforces it. `platform` and
  `fallback_platform` are accepted and not used by the package yet.
- Without `.gleon/gleon.yaml` everything behaves like Flutter: exact by default, no metrics, and
  nothing is written on passing tests.

## Metrics

Passing goldens don't show how close they came to failing. With metrics on, every comparison of
a golden covered by a rule writes a case report to `.gleon/runs/latest/cases/<test name>.json`
(overwritten by each run; `.gleon/.gitignore` ignores `runs/` and is created like `gleon init`
would if it is missing) and prints one line:

```text
gleon ✓ test/goldens/swatch.png  ssim 0.931 (≥0.800, +0.131)  color 5.2 (≤8, +2.8)  12 ms
```

Turn them on with `metrics: {enabled: true}` in `.gleon/gleon.yaml` or with the environment
variable `GLEON_METRICS=1` (which beats the file; `GLEON_METRICS=0` turns them off);
`metrics: {console: false}` keeps the files and drops the lines. A case report records the golden
and candidate SHA-256 and size, the effective tolerance and masks, the outcome (`identical`,
`match`, `mismatch`, `dimension_mismatch`, `error`, `updated`), the metrics with their headroom to
each threshold (for SSIM `min_ssim - min_similarity` and `color_tolerance - peak_excess`), the test
name, platform, Flutter version and timings. The format is a JSON Schema in the gleon repository
(`gleon-model/schema/case.v1.json`), shared with the CLI.

Use them to set tolerances from measurements instead of guesses, e.g. by collecting the reports
from CI runs on every OS. The same reports are the input of the gleon CLI's reports and history;
the CLI also keeps goldens out of Git (content-addressed blobs with small JSON manifests) and
manages per-platform baselines.

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

## Contributing

### Architecture

One package with a hard internal boundary:

```text
lib/gleon.dart            exports only (flutter_test minus matchesGoldenFile, plus the gleon API)
lib/src/core/             plain Dart: never imports Flutter (dart:ui, package:flutter*)
  compare/                GoldenTolerance, PixelRegion, MaskZone, tolerance resolution
  config/                 .gleon/gleon.yaml discovery, rule resolution (native), comparison plan
  native/                 @Native leaf bindings, ABI check, typed report and metrics parsing
  report/                 case reports, console lines
  hook/                   native targets, release download, source build (used by hook/build.dart)
  io/                     atomic file writes shared by the hook and the matcher
lib/src/flutter/          the Flutter layer: matchesGoldenFile, the comparator, case recording,
                          failure artifacts
hook/build.dart           thin build hook on top of lib/src/core/hook/
bin/                      maintainer scripts (dart:io + crypto only), run with plain `dart`
```

**Rule:** code in `lib/src/core/` must not import Flutter, so it stays usable from `dart test`,
the build hook and other SDKs later; everything Flutter-specific (`Rect`, matchers, comparators)
lives in `lib/src/flutter/` and converts to core types at the boundary. DCM enforces the rule
(`avoid-banned-imports` in `analysis_options.yaml`).

### Why leaf FFI calls

Every native call is an `isLeaf: true` call. That allows passing the PNG buffers zero-copy via
`Uint8List.address` and returning `{ptr, len}` slices by value, so the Dart side never allocates
native memory (no `package:ffi`, no `malloc`/`free` pairs, no finalizers). The price is that the
isolate group cannot reach a GC safepoint while a comparison runs (milliseconds for typical
goldens, seconds for very large SSIM comparisons). For tests that is the right trade-off: the test
awaits the result anyway, and `flutter test` parallelizes across processes. Apps that must stay
responsive would instead copy into `malloc`ed memory and make non-leaf calls in `Isolate.run`.

### Checks

```sh
dart format --set-exit-if-changed .
flutter analyze --fatal-infos     # also in example/
dcm analyze .                     # DCM 1.39.2, also in example/
flutter test                      # also in example/
```

Case reports written by the tests are validated against `case.v1.json` when a gleon checkout sits
next to this repository (`../gleon`, as in CI); without it that check is skipped.

`analysis_options.yaml` is the single, strict configuration (analyzer lints plus DCM presets);
every disabled or narrowed rule carries its reason.

## Maintainers

The native code (`gleon-engine`, `gleon-model`, `gleon-ffi`) lives in the
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
