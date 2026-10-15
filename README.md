# gleon (Flutter)

A drop-in replacement for Flutter's `matchesGoldenFile`, powered by the gleon comparison engine
(Rust, the same engine as the [gleon CLI](https://github.com/gleon-rs/gleon)): the same goldens
next to the tests, 5–20x faster comparisons, `pixel` and `ssim` tolerances, ignore regions, and
goldens with the app's real fonts that compare their text on the platform they were recorded on.
It is a comparison engine, not a golden harness: themes, locales and devices stay with your tests
or [any harness](#golden-harnesses).

> **Status: 0.5.0.** The API may still change before 1.0. Host `flutter test` on macOS arm64,
> Linux x64/arm64 (the glibc of Ubuntu 26.04 or newer; every release names the exact floor) and
> Windows x64; no Rust toolchain is needed. A real app suite of 1 800 goldens runs on it in `ssim`
> mode, and the package's own CI runs every change on all four hosts.

## Quick start

**1. Add the package** (a released tag: prebuilt libraries exist for tags only):

```yaml
dev_dependencies:
  gleon:
    git:
      url: https://github.com/gleon-rs/flutter.git
      ref: v0.5.0
```

**2. Replace one import.** Everything else from `flutter_test` stays available, and goldens
behave as in Flutter (exact, next to the test, `--update-goldens` rewrites them):

```diff
-import 'package:flutter_test/flutter_test.dart';
+import 'package:gleon/gleon.dart';
```

**3. Load the app's real fonts** (optional, recommended), once in `test/flutter_test_config.dart`:

```dart
import 'dart:async';

import 'package:gleon/gleon.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  await testMain();
}
```

(`setUpAll(loadAppFonts)` works too. Inside a test body time is fake and the font files never
load: there, `await tester.runAsync(loadAppFonts)`.)

Then run `flutter test --update-goldens` once on the platform you record goldens on, and
`flutter test` anywhere. The first `flutter test` downloads the native library of the host (see
[Install](#install)). What you get:

| You have                           | Comparison                                                                                   | Text of widgets (real fonts)                                                                               |
| ---------------------------------- | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Nothing else                       | Exact, as Flutter.                                                                           | Compared on the platform the golden was recorded on (`--update-goldens` stamps it), ignored on other OSes. |
| `tolerance:` on a call             | [`.pixel()` or `.ssim()`](#tolerance) for that golden.                                       | The same.                                                                                                  |
| [`.gleon/gleon.yaml`](#configuration-with-gleongleonyaml) | Rules per path, masks, metrics, the canonical platform of the goldens.            | The same, plus a CI job that requires every golden to be recorded on the canonical platform.               |

The example app (`example/`, a counter with real fonts) records its goldens on macOS and passes
them on Linux and Windows in CI, exact except for the text.

## Install

On the first `flutter test`, the package's build hook downloads the native library for the test
host from the GitHub Release of that version, verifies it against the release's `SHA256SUMS.txt`
(releases are immutable) and caches it in `.dart_tool/hooks_runner/shared/`. Later runs, including
offline ones, reuse the cache until `flutter clean`. `HTTPS_PROXY` is honored. The hook never
needs Rust, cargo or a compiler. A git dependency on a commit between releases (`ref: main`)
downloads the libraries of the release its version names only while they were built from the
engine commit the checkout pins; otherwise the build fails and names the tag to depend on.

Overrides (in the app's `pubspec.yaml`), e.g. for air-gapped machines or a mirror:

```yaml
hooks:
  user_defines:
    gleon:
      ffi_path: path/to/libgleon_ffi.dylib # use this library file as is
      # release_url: https://mirror.example/gleon/v0.5.0/ # SHA256SUMS.txt + assets
      # gleon_repo: ../gleon               # contributors: build from a gleon checkout
```

The first source that applies wins: `ffi_path`, then `gleon_repo`, then a library inside the
package's `native/<target>/` (a maintainer's build, or one shipped in the package), then the
download, from `release_url` when it is set (the release's directory, without a query or
fragment; `https`, or plain `http` to this machine only). `ffi_path` and `gleon_repo` must be
paths: any other value fails the build.

## Migrate

If a file must keep both imports, add `hide matchesGoldenFile` to the `flutter_test` import. To
keep Flutter's own matcher for some tests (e.g. goldens of a custom `goldenFileComparator` that is
not a `LocalFileComparator` subclass, such as a remote golden store, which gleon does not
support), import `flutter_test` with a prefix as well and call it there:

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

`tolerance` takes a `GoldenTolerance`:

```dart
// Up to 0.5% of pixels may differ.
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile(
    'goldens/my_widget.png',
    tolerance: const GoldenTolerance.pixel(maxDiffRatio: 0.005),
  ),
);

// Tolerates rendering noise (anti-aliasing, sub-pixel geometry, color drift),
// still catches changed/missing content, color and alpha changes, blur.
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile(
    'goldens/my_widget.png',
    tolerance: const GoldenTolerance.ssim(),
  ),
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

With a language version of 3.10 or newer (the `sdk` lower bound of your own `pubspec.yaml`), dot
shorthands keep call sites short: `tolerance: const .ssim()`.

| Tolerance                                          | Meaning                                                                                                                  |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `.exact()` (default)                               | Every pixel must be identical, like Flutter (text: see `textTolerance`).                                                 |
| `.pixel({maxDiffRatio = 0.01, …options})`          | At most this fraction (0.0–1.0) of pixels may differ; see [Pixel options](#pixel-options).                               |
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

Images of different sizes fail with both sizes in the message; their diff image has the larger
width and height: the area both cover compared like `exact`, the golden's own area with blue
stripes, the test image's own area with green ones.

Suite-wide tolerances per path live in `.gleon/gleon.yaml`, see below.

### Pixel options

Three options of `.pixel()`, all off by default, let some differing pixels count as equal (yellow
in the diff image, cyan for edges; case reports count them as `tolerated_pixels` and
`edge_pixels`). They are for rendering noise of shapes in a pixel comparison, not a substitute for
`.ssim()`. They never apply to text: a changed glyph keeps its whole share of its tile (see
[Real text](#real-text)). In `.gleon/gleon.yaml` they belong to `mode: pixel` rules (a config
error elsewhere).

| Option (yaml key)                        | A differing pixel counts as equal when                                      |
| ---------------------------------------- | --------------------------------------------------------------------------- |
| `channelTolerance` (`channel_tolerance`) | no RGBA byte differs by more than this (0–254): GPU and color drift.        |
| `antiAlias` (`anti_alias`)               | it looks anti-aliased in either image (the detection of pixelmatch).        |
| `edgeThreshold` (`edge_threshold`)       | the Sobel gradient of the golden's luma there exceeds this (0–254; 0: off). |

Measured on this package's anti-aliased test shape moved by 0.3 px: 611 of 9600 pixels differ
exactly, 75 with `antiAlias`, 22 with `edgeThreshold: 64`; a one-pixel dot on a flat area fails
with all three. The price of `edgeThreshold` (Skia Gold's edge mask has it too): every change
that lies on the golden's edges passes, and on the calibration corpus of the gleon engine that
includes a missing glyph, a card moved by 1 px and, at 64, a missing small icon. The gradient is
unnormalized like Skia Gold's: a sharp step of 16 luma levels already gives 64. Prefer `antiAlias`
with a small `maxDiffRatio`, or `.ssim()`.

## Real text

`flutter test` draws every glyph as the same box (the `FlutterTest` font), so goldens cannot see
text. `loadAppFonts()` (see [Quick start](#quick-start)) loads the app's real fonts instead: every
family of its `FontManifest.json` (its own fonts, those of its packages, `MaterialIcons`) and
Roboto from the Flutter SDK. Operating systems then lay text out alike (the fonts' Windows line
metrics are aligned with the ones macOS and Linux use, so line heights on Windows can differ from
the real app there), but rasterize glyphs differently: measured on CI, 40% or more of the pixels
of a 16x16 square of text differ between macOS and Linux, more than a changed digit of the same
width does (24%). No tolerance tells them apart, so a golden compares text only on the platform
it was recorded on.

gleon writes that platform into the golden itself: a `tEXt` chunk of the PNG (`gleon:platform`,
e.g. `macos-aarch64`) that image decoders ignore, so the golden stays one file next to the test,
with or without a `.gleon/gleon.yaml`. Then a golden compares in one of two ways:

1. **On the platform it was recorded on:** text is compared too. By default at most 5% of the
   pixels of any 16x16 square of text may differ: the same OS draws the same glyphs alike across
   its versions (a pixel per square, measured between macOS 15 on CI and macOS 26), a changed
   digit differs by 24%.
2. **On any other platform:** the same golden, with text ignored by default (everything else is
   compared under the golden's tolerance). Changes that move anything (a longer word, another
   weight, a shifted line) still fail; changes of text alone (a digit, a color) do not. A failure
   names the platform the golden was recorded on.

A golden without that chunk (recorded by Flutter, or by gleon before 0.5.0) counts as recorded on
the `fallback_platform` of its `.gleon/gleon.yaml`, else as recorded nowhere known: then no
platform compares its text, and a pass whose text differed says so once per test process
(`flutter test` runs each test file in its own). Record such goldens again with
`flutter test --update-goldens` on your main platform: the same image is written once more, with
its stamp. Tools that strip text chunks from PNGs (optimizers such as `oxipng --strip`) drop the
platform too.

**CI recipe:** run one job on the platform you record goldens on (a macOS runner for goldens
recorded on a Mac). It is the only job that compares text; the others compare everything else.
With a `.gleon/gleon.yaml` naming that platform as `fallback_platform`, set
`GLEON_REQUIRE_CANONICAL=1` in that job: goldens recorded on other platforms are then compared as
its own, so their glyphs fail until they are recorded there.

### Recording goldens on any platform

`flutter test --update-goldens` works on every platform and writes the golden stamped with the
platform it ran on:

| The golden                                                        | `--update-goldens`                                                                                                                                    |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Missing, recorded on this platform, or without a stamp            | written, stamped with this platform (the same image too, once, for the stamp)                                                                         |
| The same image, stamped                                           | left as it is                                                                                                                                         |
| Recorded on another platform, no `fallback_platform`              | written: nothing else could record it again                                                                                                           |
| Recorded on another platform, with a `fallback_platform`          | left as it is while only its text differs (one line says so and names the `fallback_platform`), so it never flips between platforms over their glyphs; written when anything else changes |
| Recorded elsewhere, updated on the `fallback_platform`            | written: the `fallback_platform` records it again                                                                                                     |

So a contributor on Linux adds or changes a screen with `--update-goldens`, and the golden then
compares its text on Linux and ignores it on macOS. The `fallback_platform` is the canonical
platform of a workspace: it warns about each golden recorded elsewhere (its text is not compared
there), `--update-goldens` there records them again, and `GLEON_REQUIRE_CANONICAL=1` makes it
compare them as its own (see the CI recipe above). To record goldens on the canonical platform
from CI, let a job you start by hand there run `flutter test --update-goldens` and upload the
goldens for you to commit.

`textTolerance` (0.0–1.0, or `text_tolerance` of the golden's rule) is the largest share of
differing pixels allowed in any 16x16 square of text. Unset, it depends on the golden: 0.05 on
the platform it was recorded on, 1 (text never fails) anywhere else. A value you set always
applies: lower it to compare text on other operating systems too, at your own risk, or set 1 to
turn text comparison off on the golden's platform as well:

```dart
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile(
    'goldens/my_widget.png',
    textTolerance: 0.1, // text compared on other operating systems too
  ),
);
```

The boxes of text come from the render tree: one per line of each paragraph and editable text
that is painted, grown by an eighth of the line's height for ink beyond it (diacritics, negative
letter spacing, outlined text), clipped like the text is, without `WidgetSpan`s. Text laid out
but not painted has none (the hidden pages of an `IndexedStack`, `Offstage`, `Visibility`, a
route under an opaque one), so it never hides changes of what is painted there. Rotated or skewed
text is covered by the bounding box of its lines. Icons are text too (`Icon` draws a glyph of an
icon font, which each OS rasterizes its own way): an icon swapped for another of the same size
passes on other platforms by default. A box keeps covering its text when an opaque widget is
painted over it. On macOS, at 0.1, every mutation of the package tests
fails (a changed digit with 24% of a square, a frame tight around text with 23%, the rest with
51% or more); with text ignored only those that move pixels outside the text do.

A widget (a `Finder`) or a `ui.Image` is compared as raw pixels: a PNG is encoded only to keep
the candidate of a failure (see [Metrics](#metrics)). Text applies to widgets only, with every
tolerance (with `ssim` it is judged by the same tiles and left out of both SSIM gates; a warning
when a byte or an image input leaves a `textTolerance` unused); `ignoreRegions` beat it, for
unstable backgrounds under text. Byte and image inputs (`Uint8List`, `ui.Image`) have no text
boxes: their text is compared like every other pixel, so they fail on other operating systems
wherever glyphs differ; match a widget instead.

Compared exactly, so different on other operating systems:

- Text drawn on a canvas (`TextPainter` in a `CustomPainter`, charts): it has no render object
  to take boxes from.
- `TextStyle.shadows`: Flutter's tests turn elevation shadows off (`debugDisableShadows`), not
  the shadows of text.

With `debugDefaultTargetPlatformOverride` set to iOS or macOS, Material's theme asks for Apple's
system fonts, which no test can load: that text stays in Flutter's test font (the same on every
OS, but boxes). Bundle a font and name it in the theme instead. Fonts shipped as TrueType
collections (`.ttc`) are loaded as they are, so their line heights on Windows can differ.

## Configuration with `.gleon/gleon.yaml`

Suite settings live in the [gleon CLI](https://github.com/gleon-rs/gleon)'s workspace file —
the very same file, so a project that later adopts the CLI keeps its rules. The smallest useful
one names the platform the goldens are recorded on:

```yaml
# .gleon/gleon.yaml
fallback_platform: macos-aarch64
```

Each golden belongs to the nearest directory above it with `.gleon/gleon.yaml` (its workspace;
the working directory of the test does not matter, and one test run may span several
workspaces), no further up than the repository root (the first directory with `.git`, `.hg`,
`.jj` or `.sl`), and never the home directory or a directory above it unless that is a repository
root itself (CI that points `HOME` at the checkout). The rule of a golden is resolved by its path relative
to the workspace root, with the CLI's own code; the file is read again when it changes.

```yaml
# .gleon/gleon.yaml (the gleon CLI writes one with `gleon init`)
# The canonical platform: goldens without a platform stamp were recorded there, see Real text.
fallback_platform: macos-aarch64

exclude: "test/goldens/experimental/**"

screenshots:
  # The first matching rule wins. `mode` is required: exact, pixel or ssim.
  - include: "test/goldens/**/*.png"
    mode: ssim
    diff: { min_similarity: 0.8, color_tolerance: 8 }
    masks:
      - path: "**/clock*.png"
        zones: [{ x: 0, y: 0, width: "25%", height: 40 }] # pixels or "NN%"
  - include: "test/widgets/**/*.png" # before test/**: the first match wins
    mode: exact # every pixel, no `diff` keys
  - include: "test/**/*.png"
    mode: pixel
    diff: { threshold: 0.01, anti_alias: true } # see Pixel options
    text_tolerance: 1 # see Real text

metrics:
  enabled: false

# Where the images of failing goldens are kept (relative to the workspace root).
artifacts: .gleon/runs/latest/artifacts
```

- **Globs** (`include`, `exclude`, mask `path`) match paths relative to the workspace root,
  case-insensitively: `*` and `?` stay within a directory, `**` (a whole segment) crosses
  directories, `[abc]` and `[!abc]` are character classes. `{a,b}` alternatives, `[^abc]`,
  `[/]`, `\`, a leading `/`, a `.`, `..` or empty segment and a trailing `/` are config errors
  naming the pattern: they would match differently than written, differently on Windows, or
  never.
- **`mode`** is required in every rule (`exact`, `pixel` or `ssim`): a rule without one would
  otherwise tolerate 1% of the pixels silently. **Diff keys** belong to their mode (`threshold`
  and the pixel options to `pixel`, `min_similarity` and `color_tolerance` to `ssim`, none to
  `exact`): a key of another mode is a config error, even at its default, never silently
  ignored.
- **Priority:** the `tolerance` argument of a call beats the golden's rule, which beats exact;
  `textTolerance` beats the rule's `text_tolerance`. Masks of the rule are added to the call's
  `ignoreRegions`.
- `fallback_platform` applies to every golden of the workspace, matched by a rule or not. A
  golden matched by `exclude` (or inside a directory the CLI never scans, such as `build/`) is
  the one opt-out: compared exactly, its text as pixels like the rest (unless the call sets a
  `textTolerance`), and written without a stamp, like Flutter does. A golden no
  rule matches is compared exactly and records nothing, but is stamped and tracked like the rest.
- Golden paths must be valid gleon test names (`[a-z0-9_.-]` segments, case-insensitive), as for
  `gleon stage`; an invalid config or name fails the test with the file path and the parser's
  message. Unknown keys are rejected.
- `fallback_platform` takes OS and architecture only (renderer and labels are ignored), under the
  names a process reports (`macos-aarch64`, `linux-x86_64`, `linux-aarch64`, `windows-x86_64`;
  `macos-arm64`, `linux-x64` and `darwin` are read as them). `required_version` is optional and
  only checked for syntax here (the CLI enforces it); `platform` and the `GLEON_PLATFORM` /
  `GLEON_FALLBACK_PLATFORM` variables are the CLI's and unused by the package.
  `GLEON_REQUIRE_CANONICAL` (1/0, like `GLEON_METRICS`) makes the `fallback_platform` compare
  goldens recorded elsewhere as its own.
- Without `.gleon/gleon.yaml` everything behaves like Flutter: exact by default, no metrics, and
  nothing is written on passing tests (goldens are still stamped by `--update-goldens`).

### Failure images

A failing golden covered by a rule also keeps its images in the workspace's artifacts directory,
`<artifacts>/<platform>/<test name>/golden.png`, `candidate.png` and `diff.png`, where
`<platform>` is the platform the test ran on (`macos-aarch64`, `linux-x86_64`, ...; a missing
golden keeps its candidate only), and its case report (see [Metrics](#metrics)), with or without
metrics; the failure message names the report. When the golden passes again, the images are
removed and so is the report (with metrics, the report of the pass replaces it). The directory is
`.gleon/runs/latest/artifacts` unless `artifacts:` or the environment variable
`GLEON_ARTIFACTS_DIR` (which beats the file) names another directory under `.gleon/runs/` outside
`latest/` (any other value fails every golden; `<platform>/` is added below it too), so the images
are always ignored by Git. Platforms sharing a workspace (a Mac and a Linux container on one
checkout) never overwrite each other's images or reports. To keep them on a RAM disk, link
`.gleon/runs` there. The `failures/` files next to the test are written as before.

## Metrics

Passing goldens don't show how close they came to failing. A golden covered by a rule writes a
case report to `.gleon/runs/latest/cases/<platform>/<test name>.json` when it fails, and with
metrics on for every comparison (overwritten by each run; `.gleon/.gitignore` ignores `runs/` and
is created like `gleon init` would if it is missing); metrics also print one line:

```text
gleon ✓ test/goldens/swatch.png  ssim 0.931 (≥0.800, +0.131)  color 5.2 (≤8, +2.8)  12 ms
```

Turn them on with `metrics: {enabled: true}` in `.gleon/gleon.yaml` or with the environment
variable `GLEON_METRICS` (which beats the file): `1` or `true` turns them on, `0` or `false` off
(any case, surrounding spaces ignored), an empty value counts as unset, and any other value fails
every golden. `metrics: {console: false}` keeps the files and drops the lines. A report that
cannot be written is printed as a warning and never fails the test. A case report records the
golden SHA-256 and size (and `golden.platform`, the platform its stamp names), the candidate size
and SHA-256 (a widget's raw pixels have one only when its PNG is kept), the effective tolerance
and masks, the outcome (`identical`, `match`, `mismatch`, `dimension_mismatch`, `error` with its
kind, `updated`, `missing` for a golden that does not exist yet), the metrics with their headroom
to each threshold (for SSIM `min_ssim - min_similarity` and `color_tolerance - peak_excess`), the
paths of the failure images, the test name, platform, Flutter version and timings. The format is
a JSON Schema in the gleon repository (`gleon-model/schema/case.v5.json`), shared with the CLI.

Reports of different goldens come from different test processes and stay until overwritten, so a
report does not show by itself which run wrote it. Set `GLEON_RUN_ID` (e.g.
`GLEON_RUN_ID: ${{ github.run_id }}-${{ github.run_attempt }}` in GitHub Actions; up to 128
letters, digits, `.`, `_` and `-`) to stamp every report of a run with the same id. A golden that
cannot be read or written is recorded as an `io` error.

Use them to set tolerances from measurements instead of guesses, e.g. by collecting the reports
from CI runs on every OS. The case reports are the result format of the
[gleon CLI](https://github.com/gleon-rs/gleon), which turns the reports of a run into one
(`gleon report html`, `gleon dashboard`) and approves candidates (`gleon approve`).

## Golden harnesses

Packages that build golden scenes (alchemist, golden_toolkit, golden_screenshot, …) call
`flutter_test`'s own `matchesGoldenFile`. Install `GleonFileComparator` once to compare their
goldens with gleon too:

```dart
// test/flutter_test_config.dart
import 'dart:async';

import 'package:gleon/gleon.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  goldenFileComparator = GleonFileComparator.fromExisting(goldenFileComparator);
  await testMain();
}
```

Goldens stay where they are (a `LocalFileComparator` subclass keeps naming them, through its
`getTestUri`; installing twice keeps the first); tolerances and masks come from
`.gleon/gleon.yaml`, failures and `--update-goldens` behave as with gleon's matcher. Which path
compares best:

1. **A widget (`Finder`) through gleon's `matchesGoldenFile`:** its raw pixels with the boxes of
   its text, so real text is compared right, and no PNG is encoded (see
   [Performance](#performance)). It works with `GleonFileComparator` installed too.
2. **A `ui.Image` or PNG bytes through gleon's matcher, and everything through
   `GleonFileComparator`:** best effort. The same engine and rules, but without text boxes, so
   text is compared like every other pixel; a comparator also gets a PNG that Flutter encoded
   first. Text a harness has already replaced in its image (alchemist's `obscureText` draws
   glyphs as rectangles) cannot be compared at all.

Whichever `goldenFileComparator` is assigned last wins: a harness that installs a tolerant
comparator of its own (alchemist with `diffThreshold` above 0, golden_screenshot's default
`allowedDiffPercent`, ff_golden with a non-strict tolerance) bypasses gleon or refuses to run.
Turn its threshold off and set the tolerance in `.gleon/gleon.yaml`.

alchemist can hand its widgets to gleon's matcher instead, real text included:
[doc/alchemist.md](doc/alchemist.md).

## Performance

A widget golden (a `Finder`), from the captured frame to the verdict: Flutter encodes the frame
as a PNG and compares it with its comparator (a pass short-cuts on equal bytes); gleon passes the
frame's raw pixels and encodes a PNG only to keep it (a failure); a `ui.Image` goes the same way.
Rendering the frame is the same for both and not measured. Exact, no `.gleon/` workspace; Apple
M3 Max, macOS, Flutter 3.47.6, measured with gleon 0.3.0, mean latency with
[bench_press](https://pub.dev/packages/bench_press):

| Scenario                                      | Golden    | Flutter SDK | gleon   | Speedup |
| --------------------------------------------- | --------- | ----------: | ------: | ------: |
| Passing                                       | 400x300   |     9.60 ms | 0.43 ms |     22x |
|                                               | 390x844   |     15.5 ms | 1.19 ms |     13x |
|                                               | 1170x2532 |     89.4 ms |  7.3 ms |     12x |
| Failing (small change, failure files written) | 400x300   |     43.7 ms |  1.9 ms |     23x |
|                                               | 390x844   |     77.5 ms |  4.2 ms |     18x |

Encoding the PNG is most of Flutter's cost. gleon's is reading the frame's pixels (`toByteData`,
which Flutter pays as well) and decoding the golden PNG; comparing them is a `memcmp` per equal
row. gleon's failing samples (writing files) varied too much for bench_press to resolve a ratio,
so their speedups are ratios of means.

The table leaves out what gleon adds for real text: finding the painted text of the widget (a
walk of its render tree and a replay of its paint without drawing). Measured the same way with
gleon 0.5.0: 0.6 ms for 50 lines of text, 1.9 ms for a 1170x2532 screen of 1000 rows (127
visible). Widgets full of text therefore gain less than the table shows: 0.6 ms of text on top
of the 0.43 ms of the passing 400x300 golden would bring its 22x to about 9x.

One golden comparison of PNG bytes (byte inputs), Flutter's own comparator
(`LocalFileComparator`, behind `flutter_test`'s `matchesGoldenFile`) against gleon, with the same
golden file and candidate bytes, measured inside `flutter test` (mean latency; the resolved
ratios have 95% confidence intervals within ±8%):

| Scenario                                      | Golden    | Flutter SDK | gleon (exact) | Speedup | gleon `ssim` |
| --------------------------------------------- | --------- | ----------: | ------------: | ------: | -----------: |
| Passing, identical bytes                      | 400x300   |      190 µs |         40 µs |    4.8x |        40 µs |
|                                               | 390x844   |      211 µs |         42 µs |    5.0x |        42 µs |
|                                               | 1170x2532 |      429 µs |         51 µs |    8.4x |        51 µs |
| Passing, re-encoded (same pixels)             | 400x300   |     2.95 ms |       0.52 ms |    5.6x |      0.52 ms |
|                                               | 390x844   |     8.29 ms |       1.60 ms |    5.2x |      1.61 ms |
|                                               | 1170x2532 |     56.1 ms |       8.57 ms |    6.5x |      8.68 ms |
| Failing (small change, failure files written) | 400x300   |     35.7 ms |       1.76 ms |     20x |      1.79 ms |
|                                               | 390x844   |     63.0 ms |       3.69 ms |     17x |      3.83 ms |

Across the resolved cases gleon is 5.8x faster (geometric mean; the failing ones write files and
varied too much to resolve), and tolerant `ssim` costs no more than exact. A failing 1170x2532
golden is beyond bench_press's 200 ms limit for one operation and not measured here. Flutter
decodes through the engine but inverts both images and compares them pixel by pixel in Dart, and
a failure renders two diff images and encodes four PNGs; gleon decodes and compares in Rust and
writes one diff image.

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
`gleon-engine/tests/ssim_corpus.rs` in the gleon repository; off-the-shelf crates (`image-compare`,
pixelmatch/`dify`, `butteraugli`) could not separate that corpus with any threshold. Content
whose pixels depend on the GPU or a shader (`CustomPaint` with fragment shaders) differs between
machines even on one OS: compare it under `ssim`.

## Known limitations

- `ssim` fails when glyphs move by half a pixel or more — typical of different operating
  systems' font engines — where it has no text boxes: byte and image inputs, text drawn on a
  canvas. The text of a widget is judged by its tiles instead (see Real text).
- `ssim` can pass a low-contrast color change of a one-pixel line. Use `exact`/`pixel` where every
  pixel matters.
- gleon's matcher takes the directory of the goldens from `goldenFileComparator`, which must be
  a `LocalFileComparator`: Flutter's default, a subclass of it (alchemist's, the
  `_TolerantGoldenFileComparator` example of Flutter's documentation) or `GleonFileComparator`.
  A subclass's own comparison and threshold never run; gleon's tolerance applies. Any other
  comparator (a remote golden store) fails with a message naming the ways out: remove it, or use
  `ft.matchesGoldenFile` for those tests (see [Migrate](#migrate)).
- alchemist with `obscureText` (its default for CI goldens) passes an image of blocked text: no
  text is compared there (see [doc/alchemist.md](doc/alchemist.md)).
- Web (`--platform chrome`) does not compile: the package uses `dart:ffi`. Keep web tests in files
  that import `flutter_test` (with `hide matchesGoldenFile` next to a gleon import, or a prefixed
  `ft.matchesGoldenFile`, see [Migrate](#migrate)) and run them apart.
- Linux hosts need the glibc of Ubuntu 26.04 or newer (the `PLATFORMS.txt` of each release names
  the exact version); musl (Alpine) and macOS x64 are not supported. A library the host cannot
  load fails the first golden with a message saying so and how to build one for that host.
- On-device tests and app builds for Android, iOS or other targets get no native library (the
  build hook adds none instead of failing the build), so the first `matchesGoldenFile` there fails
  with a message saying the library is missing. A desktop debug `flutter run` of an app with gleon
  in `dev_dependencies` still runs the hook and fetches the library: Flutter runs the hooks of
  dev_dependencies for every non-release build, and the hook cannot tell a test build from an app
  build.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): architecture, checks, benchmarks and how the native
library is built and released.

## License

This package is MIT licensed (see `LICENSE`). Its native library is built from the gleon crates
`gleon-engine`, `gleon-model` and `gleon-ffi` (MIT OR Apache-2.0) and the third-party crates
listed with their license texts in [NATIVE_LICENSES.md](NATIVE_LICENSES.md).
