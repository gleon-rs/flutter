# gleon (Flutter)

Drop-in replacement for Flutter's `matchesGoldenFile` with **tolerance**, **SSIM**, **ignore
regions** and **real text in goldens** (compared on the platform the goldens are recorded on), powered by the gleon Rust comparison engine (the same engine as the
[gleon CLI](https://github.com/gleon-rs/gleon)).

> **Status: proof of concept (v0).** Flutter 3.47.5+. Host `flutter test` on macOS arm64, Linux
> x64/arm64 (Ubuntu 26.04+) and Windows x64. No Rust toolchain is needed: prebuilt,
> checksum-verified native libraries are downloaded once per project.

## Install

```yaml
dev_dependencies:
  gleon:
    git:
      url: https://github.com/gleon-rs/flutter.git
      ref: v0.2.0 # a released tag: prebuilt libraries exist for tags only
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
      # release_url: https://mirror.example/gleon/v0.2.0/ # SHA256SUMS.txt + assets
      # gleon_repo: ../gleon               # contributors: build from a gleon checkout
```

The first source that applies wins: `ffi_path`, then `gleon_repo`, then a library inside the
package's `native/<target>/` (a maintainer's build, or one shipped in the package), then the
download, from `release_url` when it is set (the release's directory, without a query or
fragment). `ffi_path` and `gleon_repo` must be paths: any other value fails the build.

See [`example/`](example) for a counter app whose tests use gleon.

## Migrate

Replace one import — everything else from `flutter_test` stays available:

```diff
-import 'package:flutter_test/flutter_test.dart';
+import 'package:gleon/gleon.dart';
```

Without extra parameters the behavior is Flutter's: exact comparison, goldens resolved relative
to the test file, `flutter test --update-goldens` rewrites them, and nothing is written when
tests pass unless metrics are on (see [Metrics](#metrics)). The one difference is the text of a
widget, see [Real text](#real-text). If a file must keep both imports, add
`hide matchesGoldenFile` to the `flutter_test` import.

To keep Flutter's own matcher for some tests (e.g. goldens of a custom `goldenFileComparator`,
which gleon does not support), import `flutter_test` with a prefix as well and call it there:

```dart
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:gleon/gleon.dart';

await expectLater(
  find.byType(MyWidget),
  ft.matchesGoldenFile('goldens/my_widget.png'),
);
```

A file that also imports `golden_toolkit`, which has a `loadAppFonts` of its own, adds
`hide loadAppFonts` to one of the two imports.

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

| Tolerance                                          | Meaning                                                                                                                  |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `.exact()` (default)                               | Every pixel must be identical, like Flutter (text: see `textTolerance`).                                                 |
| `.pixel({maxDiffRatio = 0.01})`                    | At most this fraction (0.0–1.0) of pixels may differ.                                                                    |
| `.ssim({minSimilarity = 0.8, colorTolerance = 8})` | Min local SSIM of every neighborhood (0.0–1.0) and tolerated deviation beyond the local 3x3 envelope (0–255); see below. |

`ignoreRegions` (rectangles excluded from the comparison) works with every tolerance. Each
variant only has the parameters of its mode, so a setting for the wrong mode cannot be written;
out-of-range values, and ignore regions that are empty, negative or reach beyond 4294967295
pixels, throw an `ArgumentError` when the matcher is created.

On failure the test message contains the metric and the thresholds, and
`failures/<name>_masterImage.png`, `_testImage.png` and `_gleonDiff.png` are written next to the
test (like Flutter's own failure output). As in Flutter, `<name>` is only the golden's file name:
goldens of the same name in different folders, compared from tests in one directory, share these
files, and the later failure replaces the earlier one's. The artifacts directory (see
[Failure images](#failure-images)) keeps every golden apart. Warnings (masks clipped to the
image, a case report that cannot be written) are printed one per line and never fail a test. A
failure caused by a bug in gleon itself, not by the test or its files, ends with a request to
report it.

Suite-wide tolerances per path live in `.gleon/gleon.yaml`, see below.

## Real text

`flutter test` draws every glyph as the same box (the `FlutterTest` font), so goldens cannot see
text. `loadAppFonts()` loads the app's real fonts instead: every family of its
`FontManifest.json` (its own fonts, those of its packages, `MaterialIcons`) and Roboto from the
Flutter SDK. Call it once from `test/flutter_test_config.dart`:

```dart
import 'dart:async';

import 'package:gleon/gleon.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  await testMain();
}
```

Operating systems then lay text out alike (the fonts' Windows line metrics are aligned with the
ones macOS and Linux use, so line heights on Windows can differ from the real app there), but
rasterize glyphs differently. Measured on CI, 40% or more of the pixels of a 16x16 square of
text differ between macOS and Linux, more than a changed digit of the same width does (24%). No
tolerance tells them apart, so a golden compares text only on the platform it was recorded on.
Name that platform `fallback_platform` in `.gleon/gleon.yaml` (`<os>-<arch>` with the names a
process reports: `macos-aarch64`, `linux-x86_64`, `linux-aarch64`, `windows-x86_64`; `macos-arm64`
or `darwin` fail every golden of the workspace with a config error, since they would never
match). Then a golden `goldens/a.png` compares in one of three ways:

1. **On its own platform** (`fallback_platform`): text is compared too. By default at most 5% of
   the pixels of any 16x16 square of text may differ: the same OS draws the same glyphs alike
   across its versions (a pixel per square, measured between macOS 15 on CI and macOS 26), a
   changed digit differs by 24%.
2. **On another platform with its own golden** `goldens/<os>-<arch>/a.png`: compared like the
   first. `flutter test --update-goldens` on that platform writes this file and never the shared
   one (see [Recording per-platform goldens](#recording-per-platform-goldens)).
3. **On another platform without its own golden yet:** the shared golden, with text ignored by
   default (everything else is compared exactly). Changes that move anything (a longer word,
   another weight, a shifted line) still fail; changes of text alone (a digit, a color) do not.
   A failure says which golden it compared and which file would compare text.

Without `fallback_platform` nobody knows where the goldens were recorded, so every platform
compares them the third way. The test name, rules and failure files use `goldens/a.png` on
every platform.

### Recording per-platform goldens

Run `flutter test --update-goldens` on the platform whose goldens you want: locally, in Docker
for Linux (`linux-aarch64` on Apple silicon, `linux-x86_64` with `--platform linux/amd64`), or
in a CI job you start by hand on each OS that uploads its `goldens/<os>-<arch>/` directories for
you to commit. On the goldens' own platform it rewrites the shared goldens; on every other one it
writes only that platform's own.

`textTolerance` (0.0–1.0, or `text_tolerance` of the golden's rule) is the largest share of
differing pixels allowed in any 16x16 square of text. Unset, it depends on the golden: 0.05 in
the first two ways, 1 (text never fails) in the third. A value you set always applies: lower it
to compare text against another OS's golden too, at your own risk, or set 1 to turn text
comparison off on the goldens' platform as well:

```dart
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile(
    'goldens/my_widget.png',
    textTolerance: 0.1, // text compared against another OS's golden too
  ),
);
```

The boxes of text come from the render tree: one per line of each paragraph and editable text,
grown by an eighth of the line's height for ink beyond it (diacritics, negative letter spacing,
outlined text), clipped like the text is, without `WidgetSpan`s. On macOS, at 0.1, every
mutation of the package tests fails (a changed digit with 24% of a square, a frame tight around
text with 23%, the rest with 51% or more); with text ignored only those that move pixels outside
the text do.

A widget (a `Finder`) or a `ui.Image` is compared as raw pixels: a PNG is encoded only to keep
the candidate, for a failure or a recorded pass that differs from another platform's golden (see
[Metrics](#metrics)). Text applies to widgets only, with an exact or pixel tolerance
(`ArgumentError` with `ssim`; a warning when an SSIM rule, a byte or an image input leaves a
`textTolerance` unused); `ignoreRegions` beat
it, for unstable backgrounds under text. Without a `textTolerance`, the `text_tolerance` of the
golden's `.gleon/gleon.yaml` rule applies, else the golden's default (0.05 or 1, see above).
Byte and image inputs (`Uint8List`, `ui.Image`) have no text boxes: their text is compared like
every other pixel, so against another OS's golden they need their own per-platform golden.

Compared exactly, so different on other operating systems:

- Text drawn on a canvas (`TextPainter` in a `CustomPainter`, charts): it has no render object
  to take boxes from.
- `TextStyle.shadows`: Flutter's tests turn elevation shadows off (`debugDisableShadows`), not
  the shadows of text.

With `debugDefaultTargetPlatformOverride` set to iOS or macOS, Material's theme asks for Apple's
system fonts, which no test can load: that text stays in Flutter's test font (the same on every
OS, but boxes). Bundle a font and name it in the theme instead.

## Configuration with `.gleon/gleon.yaml`

Suite settings live in the [gleon CLI](https://github.com/gleon-rs/gleon)'s workspace file —
the very same file, so a project that later adopts the CLI keeps its rules. Each golden belongs to
the nearest directory above it with `.gleon/gleon.yaml` (its workspace; the working directory of
the test does not matter, and one test run may span several workspaces). The rule of a golden is
resolved by its path relative to that directory, with the CLI's own code; the file is read again
when it changes. The search does not stop at the repository root, so a stray `.gleon/gleon.yaml`
in a directory above the project (e.g. `~/.gleon/gleon.yaml`) applies to goldens without a closer
one.

```yaml
# .gleon/gleon.yaml (create it by hand or with `gleon init`)
required_version: ">=0.1.0"

# Where the goldens are recorded: text is compared there, see Real text.
fallback_platform: macos-aarch64

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
    text_tolerance: 1 # pixel only, see Real text (1: text never fails, on every platform)

metrics:
  enabled: false

# Where the images of failing goldens are kept (relative to the workspace root).
artifacts: .gleon/runs/latest/artifacts
```

- **Priority:** the `tolerance` argument of a call beats the golden's rule, which beats exact;
  `textTolerance` beats the rule's `text_tolerance`. Masks of the rule are added to the call's
  `ignoreRegions`.
- A golden matched by `exclude` (or inside a directory the CLI never scans, such as `build/`) or
  by no rule is compared exactly, like without the file: one golden for every platform, whatever
  `fallback_platform` says.
- Golden paths must be valid gleon test names (`[a-z0-9_.-]` segments, case-insensitive), as for
  `gleon stage`; an invalid config or name fails the test with the file path and the parser's
  message. Unknown keys are rejected.
- `required_version` is only checked for syntax here; the CLI enforces it. `fallback_platform`
  is the platform of the goldens (see Real text; OS and architecture only, renderer and labels
  are ignored). `platform` and the `GLEON_PLATFORM` / `GLEON_FALLBACK_PLATFORM` variables are the
  CLI's and unused by the package.
- Without `.gleon/gleon.yaml` everything behaves like Flutter: exact by default, no metrics, and
  nothing is written on passing tests.

### Failure images

A failing golden covered by a rule also keeps its images in the workspace's artifacts directory,
`<artifacts>/<test name>/golden.png`, `candidate.png` and `diff.png` (a missing golden keeps its
candidate only), and its case report (see
[Metrics](#metrics)), with or without metrics; when the golden passes again, the images are
removed and so is the report (with metrics, the report of the pass replaces it, and a pass that
differs from another platform's golden keeps its `candidate.png`). The directory
is `.gleon/runs/latest/artifacts` unless
`artifacts:` or the environment variable `GLEON_ARTIFACTS_DIR` (which beats the file) names
another directory under `.gleon/runs/` outside `latest/` (any other value fails every golden), so
the images are always ignored by Git. To keep them on a RAM disk,
link `.gleon/runs` there. The `failures/` files next to the test are written as before.

## Metrics

Passing goldens don't show how close they came to failing. A golden covered by a rule writes a
case report to `.gleon/runs/latest/cases/<test name>.json` when it fails, and with metrics on
for every comparison (overwritten by each run; `.gleon/.gitignore` ignores `runs/` and is created
like `gleon init` would if it is missing); metrics also print one line:

```text
gleon ✓ test/goldens/swatch.png  ssim 0.931 (≥0.800, +0.131)  color 5.2 (≤8, +2.8)  12 ms
```

Turn them on with `metrics: {enabled: true}` in `.gleon/gleon.yaml` or with the environment
variable `GLEON_METRICS` (which beats the file): `1` or `true` turns them on, `0` or `false` off
(any case, surrounding spaces ignored), an empty value counts as unset, and any other value fails
every golden. `metrics: {console: false}` keeps the files and drops the lines. A
report that cannot be written is printed as a warning and never fails the test. A case report
records the golden SHA-256 and size (of the compared golden; `golden.fallback` names another
platform's shared golden compared in place of this platform's own), the candidate size and SHA-256
(a widget's raw pixels have one only when its PNG is kept), the effective tolerance and masks, the
outcome
(`identical`, `match`, `mismatch`, `dimension_mismatch`, `error` with its kind, `updated`,
`missing` for a golden that does not exist yet), the metrics with their headroom to each threshold
(for SSIM `min_ssim - min_similarity` and `color_tolerance - peak_excess`), the paths of the
failure images, the test name, platform, Flutter version and timings. The format is a JSON Schema
in the gleon repository (`gleon-model/schema/case.v2.json`), shared with the CLI.

Reports of different goldens come from different test processes and stay until overwritten, so a
report does not show by itself which run wrote it. Set `GLEON_RUN_ID` (e.g.
`GLEON_RUN_ID: ${{ github.run_id }}-${{ github.run_attempt }}` in GitHub Actions; up to 128
letters, digits, `.`, `_` and `-`) to stamp every report of a run with the same id. A golden that
cannot be read or written is recorded as an `io` error.

Use them to set tolerances from measurements instead of guesses, e.g. by collecting the reports
from CI runs on every OS.

The case reports are the result format of the [gleon CLI](https://github.com/gleon-rs/gleon),
which can turn them into reports of a run.

## Performance

A widget golden (a `Finder`), from the captured frame to the verdict: Flutter encodes the frame
as a PNG and compares it with its comparator (a pass short-cuts on equal bytes); gleon passes the
frame's raw pixels and encodes a PNG only to keep it (a failure, or with metrics a pass that
differs from another platform's golden); a `ui.Image` goes the same way. Rendering the frame is the same for both
and not measured. Exact, no `.gleon/` workspace; Apple M3 Max, macOS, Flutter 3.47.6, mean
latency with [bench_press](https://pub.dev/packages/bench_press):

| Scenario                                      | Golden    | Flutter SDK | gleon   | Speedup |
| --------------------------------------------- | --------- | ----------: | ------: | ------: |
| Passing                                       | 400x300   |     9.49 ms | 0.46 ms |     20x |
|                                               | 390x844   |     15.2 ms | 1.25 ms |     12x |
|                                               | 1170x2532 |     87.8 ms |  7.7 ms |     11x |
| Failing (small change, failure files written) | 400x300   |     43.3 ms |  3.1 ms |     14x |
|                                               | 390x844   |     77.0 ms |  6.0 ms |     13x |

Encoding the PNG is most of Flutter's cost. The 390x844 and 1170x2532 passes resolve to 12.1x and
11.4x with 95% confidence intervals within ±1%; gleon's other samples (sub-millisecond, or
writing files) varied too much for bench_press to resolve a ratio.

One golden comparison of PNG bytes (byte inputs), Flutter's own comparator
(`LocalFileComparator`, behind `flutter_test`'s `matchesGoldenFile`) against gleon, with the same
golden file and candidate bytes. Measured inside `flutter test`, where golden tests run, with
[bench_press](https://pub.dev/packages/bench_press) (mean latency; every ratio has a 95% confidence
interval within ±8%). Apple M3 Max, macOS, Flutter 3.47.5:

| Scenario                                      | Golden    | Flutter SDK | gleon (exact) | Speedup | gleon `ssim` |
| --------------------------------------------- | --------- | ----------: | ------------: | ------: | -----------: |
| Passing, identical bytes                      | 400x300   |      191 µs |         34 µs |    5.7x |        34 µs |
|                                               | 390x844   |      213 µs |         36 µs |    5.9x |        36 µs |
|                                               | 1170x2532 |      423 µs |         45 µs |    9.5x |        45 µs |
| Passing, re-encoded (same pixels)             | 400x300   |     2.95 ms |       0.53 ms |    5.5x |      0.52 ms |
|                                               | 390x844   |     7.67 ms |       1.57 ms |    4.9x |      1.57 ms |
|                                               | 1170x2532 |     56.4 ms |        9.1 ms |    6.2x |       9.3 ms |
| Failing (small change, failure files written) | 400x300   |     34.6 ms |       1.96 ms |   17.6x |      1.85 ms |
|                                               | 390x844   |     61.1 ms |       4.44 ms |   13.8x |      4.07 ms |

Across all cases gleon is 7.7x faster (geometric mean), and tolerant `ssim` costs no more than
exact. A failing 1170x2532 golden takes Flutter about 0.4 s and gleon 25 ms; that case is beyond
bench_press's 200 ms limit for one operation, so it is a plain timing. Flutter decodes through the
engine but inverts both images and compares them pixel by pixel in Dart, and a failure renders two
diff images and encodes four PNGs; gleon decodes and compares in Rust and writes one diff image.
gleon here runs without a `.gleon/` workspace (exact, nothing recorded, like Flutter).

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
  systems' font engines. Use real fonts with `exact` or `pixel` instead (see Real text: text is
  ignored against another OS's golden by default).
- `ssim` can pass a low-contrast color change of a one-pixel line. Use `exact`/`pixel` where every
  pixel matters.
- Only Flutter's default `LocalFileComparator` is supported as the underlying golden store.
  Custom `goldenFileComparator`s, tolerant ones included (alchemist's, or the
  `_TolerantGoldenFileComparator` example of Flutter's documentation), fail with a message naming
  the ways out: remove the custom comparator, or use `ft.matchesGoldenFile` for those tests (see
  [Migrate](#migrate)).
- Web (`--platform chrome`) does not compile: the package uses `dart:ffi`.
- On-device tests and app builds for Android, iOS or other targets get no native library (the
  build hook adds none instead of failing the build), so the first `matchesGoldenFile` there fails
  with a message saying the library is missing. A desktop debug `flutter run` of an app with gleon
  in `dev_dependencies` still runs the hook and fetches the library: Flutter runs the hooks of
  dev_dependencies for every non-release build, and the hook cannot tell a test build from an app
  build.

## Contributing

### Architecture

One package with a hard internal boundary:

```text
lib/gleon.dart            exports only (flutter_test minus matchesGoldenFile, plus the gleon API)
lib/src/core/             plain Dart: never imports Flutter (dart:ui, package:flutter*)
  compare/                GoldenTolerance, PixelRegion (the call's tolerances,
                          masks and text regions)
  config/                 GleonIntegration (who calls), GleonSession (the native session)
  native/                 @Native leaf bindings, NativeEngine (ABI check, packing), verdicts,
                          error kinds
  hook/                   what hook/build.dart needs: NativeLibrary (which library, in which
                          order), UserDefines (hooks-free, so tests pass plain maps) and its
                          HookUserDefines adapter (imported by the hook only), native targets,
                          release download, source build, atomic writes
lib/src/flutter/          the Flutter layer: matchesGoldenFile, the widget capture and its text
                          regions, the comparator, loadAppFonts, FlutterSession (this package
                          as an integration)
hook/build.dart           thin build hook on top of lib/src/core/hook/
bin/                      maintainer scripts (dart:*, crypto and this package only), run with
                          plain `dart`: build_native, native_licenses, check_cases (CI)
  src/                    their logic, tested in test/tooling/ (neither is published):
                          CaseCheck, LicenseCrate and NativeLicenses, NativeBuild (install,
                          checkout state), and the shared command line (cli.dart)
```

The native engine (`gleon-ffi`) does the whole job of a golden: it finds the workspace, resolves
the `.gleon/gleon.yaml` rule, reads and compares the golden, and writes failure artifacts, case
reports and updated goldens; this package passes facts (paths, the raw pixels or PNG, the call's
tolerance, masks and text regions) and shows the verdict and texts it gets back. The C types and bindings of that contract
live together in `lib/src/core/native/gleon_ffi.dart`.

**Rule:** code in `lib/src/core/` must not import Flutter, so it stays usable from `dart test`,
the build hook and other SDKs later; everything Flutter-specific (`Rect`, matchers, comparators)
lives in `lib/src/flutter/` and converts to core types at the boundary. DCM enforces the rule
(`avoid-banned-imports` in `analysis_options.yaml`).

### Why leaf FFI calls

Every native call is an `isLeaf: true` call. That allows passing the PNG zero-copy via
`Uint8List.address` (and a call's strings as one UTF-8 buffer plus a `Uint32List` of their
lengths) and returning `{ptr, len}` slices by value, so the Dart side never allocates native memory
(no `package:ffi`, no `malloc`/`free` pairs; only the session is released by a `NativeFinalizer`).
The price is that the isolate group cannot reach a GC safepoint while a comparison runs
(milliseconds for typical goldens, seconds for very large SSIM comparisons). For tests that is the right trade-off: the test
awaits the result anyway, and `flutter test` parallelizes across processes. Apps that must stay
responsive would instead copy into `malloc`ed memory and make non-leaf calls in `Isolate.run`.

### Checks

```sh
dart format --set-exit-if-changed .
flutter analyze --fatal-infos     # also in example/
dcm analyze .                     # DCM 1.39.2, also in example/
flutter test                      # also in example/
```

Case reports written by the tests are validated against `case.v2.json` of the pinned commit
(`native/gleon_ref`, read with `git show` whatever the checkout's own state) when a gleon checkout
that has that commit sits next to this repository (`../gleon`, as in CI); without it that check is
skipped.

`analysis_options.yaml` is the single, strict configuration (analyzer lints plus DCM presets);
every disabled or narrowed rule carries its reason.

### Benchmarks

`benchmark/` holds [bench_press](https://pub.dev/packages/bench_press) benchmarks that need the
Flutter engine (`dart:ui`), so they run under `flutter test`, not `dart run bench_press run`:

```sh
flutter test benchmark/      # ~3 min; results in build/benchmark/*.json
dart run bench_press report --from-json build/benchmark/golden_comparison.json
dart run bench_press report --from-json build/benchmark/widget_capture.json
```

To check a change for regressions, keep the JSON of a run before it and compare
(`dart run bench_press diff old.json build/benchmark/golden_comparison.json`). Run on an idle
machine: bench_press withholds ratios of unstable samples ("unresolved"). `BENCH_PRESS_ARGS`
passes options (`--validate` for a smoke run, as CI does; `--trials 30`). The manual
**Benchmark** workflow runs them on every supported host and puts the report into each job's
summary.

## Maintainers

The native code (`gleon-engine`, `gleon-model`, `gleon-ffi`) lives in the
[gleon repository](https://github.com/gleon-rs/gleon); `native/gleon_ref` pins the commit CI builds.
Build the library for this machine into `native/<target>/` (the hook prefers it over downloading):

```sh
dart bin/build_native.dart                 # host; --target all: every target this host can
```

Use plain `dart`, not `dart run`: `dart run` executes the build hook first. `--target all` builds
all four targets on macOS and all but macOS elsewhere; Linux targets of another OS or
architecture need zig and `cargo-zigbuild` (`cargo install --locked cargo-zigbuild` on any host),
Windows from macOS or Linux `cargo-xwin`. CI builds every target natively. A library is replaced
atomically and stamped only after it; the `--dist` copy (release assets) comes last. A build
records the gleon commit it was made from, and the hook uses it only while `native/gleon_ref` pins
that commit. To try an unmerged engine change on top of the pinned commit, build with
`--allow-dirty` (and rebuild after every change: the hook cannot tell two dirty builds apart); to
test another checkout, use the `gleon_repo` user-define. That build runs inside Flutter's hooks
runner, which passes on only part of the environment: `RUSTFLAGS` and `RUSTC_WRAPPER` never
reach it, and `CARGO_*`/`RUSTUP_*` only from Flutter 3.49. Use `CARGO_BUILD_RUSTFLAGS` /
`CARGO_BUILD_RUSTC_WRAPPER` (Flutter 3.49+), a `.cargo/config.toml` in the checkout, or
`bin/build_native.dart`, which sees the whole environment.

`NATIVE_LICENSES.md` lists every crate linked into the library with its license texts and names
the pinned commit it was generated for. After moving `native/gleon_ref`, regenerate it (CI checks
it). The gleon repo must be at the pinned commit: its `git rev-parse HEAD` is checked; for a tree
exported without git, pass the commit with `--commit`. To leave your gleon checkout alone:

```sh
dart bin/native_licenses.dart              # --check: fail when it is stale
git -C ../gleon archive "$(cat native/gleon_ref)" | tar -x -C /tmp/gleon-pin
dart bin/native_licenses.dart --gleon-repo /tmp/gleon-pin --commit "$(cat native/gleon_ref)"
```

Releasing: bump `version` in `pubspec.yaml`, `FlutterSession.packageVersion` and `CHANGELOG.md`,
update `native/gleon_ref` (and `NATIVE_LICENSES.md`) if the engine changed, and push the tag
`vX.Y.Z`. The release workflow builds and tests all targets on
their own OS, attaches the libraries and `SHA256SUMS.txt` to an immutable GitHub Release, and then
verifies the download path on every OS.

## License

This package is MIT licensed (see `LICENSE`). Its native library is built from the gleon crates
`gleon-engine`, `gleon-model` and `gleon-ffi` (MIT OR Apache-2.0) and the third-party crates
listed with their license texts in [NATIVE_LICENSES.md](NATIVE_LICENSES.md).
