# gleon

A drop-in replacement for Flutter's `matchesGoldenFile`, with a comparison engine in Rust (the
same engine as the [gleon CLI](https://github.com/gleon-rs/gleon)):

- **5–20x faster** than Flutter's own comparator ([Performance](#performance)).
- **Tolerances:** `pixel` (a share of the pixels may differ) and `ssim` (rendering noise passes,
  changed content fails), plus ignore regions.
- **Real fonts:** goldens show the app's real text. A golden compares its text on the platform
  that recorded it and ignores the glyphs on other platforms ([Real text](#real-text)).
- **The same workflow:** PNG goldens next to the tests, `--update-goldens` writes them. No Rust
  toolchain is needed.

gleon compares goldens; it is not a golden harness. Themes, locales and devices stay with your
tests or [your harness](#golden-harnesses).

Requires Flutter 3.50 (Dart 3.14) or newer. `flutter test` runs on macOS arm64, Linux x64 and
arm64 (Ubuntu 26.04 or newer) and Windows x64. The API can change before 1.0.

## Quick start

1. Add the package:

   ```bash
   flutter pub add dev:gleon
   ```

2. Replace one import. All of `flutter_test` stays available, and goldens behave as in Flutter
   (exact, next to the test, `--update-goldens` writes them):

   ```diff
   -import 'package:flutter_test/flutter_test.dart';
   +import 'package:gleon/gleon.dart';
   ```

3. Optional, recommended: load the app's real fonts once, in `test/flutter_test_config.dart`:

   ```dart
   import 'dart:async';

   import 'package:gleon/gleon.dart';

   Future<void> testExecutable(FutureOr<void> Function() testMain) async {
     await loadAppFonts();
     await testMain();
   }
   ```

Run `flutter test --update-goldens` once on the platform where you record goldens. Then run
`flutter test` on any platform.

| You use                                                         | Comparison                                                | Text of widgets (real fonts)                                                |
| --------------------------------------------------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------- |
| Only the import                                                 | Exact, as in Flutter                                      | Compared on the platform that recorded the golden, ignored on the others    |
| `tolerance:` on a call                                          | [`.pixel(…)` or `.ssim()`](#tolerance) for that golden    | The same                                                                    |
| [`.gleon/gleon.yaml`](#configuration-with-gleongleonyaml)       | Rules per path, masks, metrics, the canonical platform    | The same; CI can require every golden to be recorded on the canonical one  |

### Migrate

A file that must keep the `flutter_test` import adds `hide matchesGoldenFile` to it.

<details>
<summary>Flutter's matcher for some tests, golden_toolkit, fonts in a test body</summary>

- To keep Flutter's own matcher for some tests (for example a `goldenFileComparator` that is no
  `LocalFileComparator`, such as a remote golden store, which gleon does not support), import
  `flutter_test` with a prefix too:

  ```dart
  import 'package:flutter_test/flutter_test.dart' as ft;
  import 'package:gleon/gleon.dart';

  await expectLater(
    find.byType(MyWidget),
    ft.matchesGoldenFile('goldens/my_widget.png'),
  );
  ```

- `golden_toolkit` has its own `loadAppFonts`: add `hide loadAppFonts` to one of the two imports.
- `setUpAll(loadAppFonts)` also loads the fonts. In a test body the time is fake and font files
  never load: use `await tester.runAsync(loadAppFonts)` there.

</details>

## Tolerance

`tolerance` takes a `GoldenTolerance`; `ignoreRegions` works with each of them:

```dart
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile(
    'goldens/my_widget.png',
    tolerance: const GoldenTolerance.ssim(),
    ignoreRegions: [const Rect.fromLTWH(0, 0, 400, 80)], // pixels of the golden PNG
  ),
);
```

| Tolerance                                     | The golden passes when                                                                                       |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `.exact()`                                    | every pixel is identical, as in Flutter. Without `tolerance`, the golden's rule applies, else this.         |
| `.pixel(maxDiffRatio: 0.005)`                 | at most this share of the pixels differs (0.0–1.0; see "Pixel options" below for rendering noise).          |
| `.ssim(minSimilarity: 0.8, colorTolerance: 8)` | only rendering noise differs (anti-aliasing, sub-pixel shifts, color drift). Changed or missing content, color, alpha and blur fail. |

Each variant takes only the parameters of its mode. Out-of-range values, and ignore regions that
are empty or negative, throw an `ArgumentError` when the matcher is created. With a language
version of 3.10 or newer, dot shorthands keep calls short: `tolerance: const .ssim()`. Rules for
many goldens go into [`.gleon/gleon.yaml`](#configuration-with-gleongleonyaml).

A failure shows the metric and the thresholds, and writes `failures/<name>_masterImage.png`,
`_testImage.png` and `_gleonDiff.png` next to the test, like Flutter does.

<details>
<summary>Pixel options: count rendering noise of shapes as equal</summary>

Three options of `.pixel(maxDiffRatio: …)`, all off by default, count some differing pixels as
equal (yellow in the diff image, cyan for edges). They never apply to text. In
`.gleon/gleon.yaml` they belong to `mode: pixel` rules.

| Option (yaml key)                        | A differing pixel counts as equal when                                      |
| ---------------------------------------- | --------------------------------------------------------------------------- |
| `channelTolerance` (`channel_tolerance`) | no RGBA byte differs by more than this (0–254): GPU and color drift.        |
| `antiAlias` (`anti_alias`)               | it looks anti-aliased in either image (the detection of pixelmatch).        |
| `edgeThreshold` (`edge_threshold`)       | the Sobel gradient of the golden's luma there exceeds this (0–254; 0: off). |

On an anti-aliased shape moved by 0.3 px, 611 of 9600 pixels differ exactly, 75 with
`antiAlias`, 22 with `edgeThreshold: 64`; a one-pixel dot on a flat area fails with all three.
`edgeThreshold` lets every change on the golden's edges pass, also a missing glyph, a card moved
by 1 px and, at 64, a missing small icon. Prefer `antiAlias` with a small `maxDiffRatio`, or
`.ssim()`.

</details>

<details>
<summary>How <code>ssim</code> decides</summary>

Two gates, both computed only around the pixels that differ:

1. **Envelope gate** (full resolution): each pixel of one image must lie within the value range
   of the other image's 3x3 neighborhood (premultiplied RGBA, so alpha counts), widened by
   `colorTolerance` and a share of the local contrast. Re-rasterization and sub-pixel shifts give
   values between neighbors; new content, color and alpha changes do not. Unexplained pixels fail
   as regions of 3 or more pixels, or with a strong deviation.
2. **Structural gate** (half resolution, as in MS-SSIM): the _minimum_ local SSIM (11x11 Gaussian
   window) must reach `minSimilarity`. This catches blur. The minimum, not the mean, so a small
   change on a large golden is not averaged away.

The defaults come from a corpus of rendering noise and regressions
(`gleon-engine/tests/ssim_corpus.rs` in the gleon repository). Content that a GPU or a shader
draws differs between machines even on one OS: compare it under `ssim`.

</details>

<details>
<summary>Failure output in detail</summary>

- `<name>` is the file name of the golden only, as in Flutter: goldens of the same name in
  different folders, compared from tests in one directory, share these files. The
  [failure images](#metrics) of a workspace keep each golden apart.
- Images of different sizes fail with both sizes in the message. The diff image has the larger
  width and height: the common area compared like `exact`, the golden's own area with blue
  stripes, the test image's own area with green ones.
- Warnings (masks clipped to the image, a case report that cannot be written) print one line each
  and never fail a test.
- A failure caused by a bug in gleon, not by the test or its files, asks you to report it.

</details>

## Real text

`flutter test` draws every glyph as the same box, so goldens cannot see text. `loadAppFonts()`
loads the app's real fonts (each family of its `FontManifest.json`, `MaterialIcons` and Roboto).
But each operating system rasterizes glyphs in its own way: about 40% of the pixels of a 16x16
square of text differ between macOS and Linux, more than a changed digit (24%). So gleon compares
the text of a golden only on the platform that recorded it:

- `--update-goldens` writes that platform into the golden: a `gleon:platform` text chunk of the
  PNG, which image decoders ignore. The golden stays one file next to the test.
- **On that platform** at most 5% of the pixels of each 16x16 square of text may differ. A
  changed digit fails.
- **On other platforms** text is ignored. All else is compared under the golden's tolerance, so a
  longer word, another font weight or a moved line still fails.

**CI:** run one job on the platform that records your goldens (a macOS runner for goldens of a
Mac). Only this job compares text. With that platform as `fallback_platform` in
`.gleon/gleon.yaml`, set `GLEON_REQUIRE_CANONICAL=1` in this job: goldens recorded on other
platforms then fail there until they are recorded on it.

### Recording goldens on any platform

`flutter test --update-goldens` works on every platform and stamps the golden with that platform.
A contributor on Linux can add a screen: its golden compares text on Linux and ignores it on
macOS.

<details>
<summary>What <code>--update-goldens</code> does with an existing golden</summary>

| The golden                                               | `--update-goldens`                                                                                                                       |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Missing, recorded on this platform, or without a stamp   | written and stamped with this platform (the same image too, once, for the stamp)                                                        |
| The same image, stamped                                  | kept                                                                                                                                     |
| Recorded on another platform, no `fallback_platform`     | written: no other platform could record it again                                                                                         |
| Recorded on another platform, with a `fallback_platform` | kept while only its text differs (one line says so), so it never flips between platforms over their glyphs; written when all else changes |
| Recorded elsewhere, updated on the `fallback_platform`   | written: the `fallback_platform` records it again                                                                                        |

The `fallback_platform` is the canonical platform of a workspace. It warns about each golden
recorded elsewhere (their text is not compared there), and `--update-goldens` there records them
again. To record on it from CI, let a job there run `flutter test --update-goldens` and upload the
goldens, or let the [gleon CLI](#the-gleon-cli-optional) commit the candidates of a failed run
with `/gleon approve`.

</details>

<details>
<summary><code>textTolerance</code>: compare text on other platforms too, or never</summary>

`textTolerance` (0.0–1.0, or `text_tolerance` of the golden's rule) is the largest share of
differing pixels in any 16x16 square of text. Unset, it is 0.05 on the golden's platform and 1
(text never fails) on the others. A value you set applies on every platform: lower it to compare
text on other operating systems too (at your own risk), or set 1 to never compare text.

```dart
await expectLater(
  find.byType(MyWidget),
  matchesGoldenFile('goldens/my_widget.png', textTolerance: 0.1),
);
```

</details>

<details>
<summary>Goldens without a stamp</summary>

A golden without the stamp (recorded by Flutter, or by gleon before 0.5.0) counts as recorded on
the `fallback_platform` of its `.gleon/gleon.yaml`. Without one, no platform compares its text,
and a pass whose text differed says so once per test process. Run `flutter test --update-goldens`
on your main platform to stamp such goldens: the same image is written once more. PNG optimizers
that strip text chunks (`oxipng --strip`) remove the stamp.

</details>

<details>
<summary>Which text is compared as text</summary>

- The boxes of text come from the render tree: one per line of each painted paragraph and
  editable text, grown by an eighth of the line height for ink beyond it, clipped like the text.
  Text that is laid out but not painted (`Offstage`, `Visibility`, the hidden pages of an
  `IndexedStack`, a route under an opaque one) has no box. A rotated or skewed line is covered by
  pieces about as long as it is high.
- Icons are text too: an icon swapped for another of the same size passes on other platforms.
- Only widgets (a `Finder`) have text boxes. Byte and image inputs (`Uint8List`, `ui.Image`)
  compare text like all other pixels, so they fail on other operating systems where glyphs
  differ: match a widget instead. `ignoreRegions` beat text boxes.
- Compared exactly, so different on other operating systems: text drawn on a canvas
  (`TextPainter` in a `CustomPainter`, charts) and `TextStyle.shadows`.
- With `debugDefaultTargetPlatformOverride` set to iOS or macOS, Material asks for Apple's system
  fonts, which no test can load: that text stays in boxes. Bundle a font and name it in the theme.
- Windows line metrics of the fonts are aligned with those of macOS and Linux, so line heights on
  Windows can differ from the real app there. TrueType collections (`.ttc`) load as they are.

</details>

## Configuration with `.gleon/gleon.yaml`

Rules for many goldens live in `.gleon/gleon.yaml`, the workspace file of the
[gleon CLI](https://github.com/gleon-rs/gleon). It is the same file, so a project that adopts
the CLI later keeps its rules. Without it, gleon behaves like Flutter. The smallest useful file
names the platform that records the goldens:

```yaml
# .gleon/gleon.yaml
fallback_platform: macos-aarch64
```

<details>
<summary>A full example</summary>

```yaml
# .gleon/gleon.yaml (the gleon CLI writes one with `gleon init`)
# For the gleon CLI: the goldens are the baselines (the package ignores this line).
baselines: goldens

# The canonical platform: goldens without a stamp were recorded there (see Real text).
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
  - include: "test/widgets/**/*.png"
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

</details>

<details>
<summary>How the rules apply</summary>

- **Workspace:** a golden belongs to the nearest directory above it with `.gleon/gleon.yaml`. The
  search stops at the repository root (`.git`, `.hg`, `.jj` or `.sl`) and never takes the home
  directory or a directory above it, unless that is a repository root. The working directory of
  the test does not matter; the file is read again when it changes.
- **Globs** (`include`, `exclude`, mask `path`) match paths relative to the workspace root, without
  case: `*` and `?` stay within a directory, `**` crosses directories, `[abc]` and `[!abc]` are
  classes. `{a,b}`, `[^abc]`, `\`, a leading `/`, a `.`, `..` or empty segment and a trailing `/`
  are config errors: they would match differently than written.
- **`mode`** is required in each rule, and `pixel` requires `diff.threshold`. A `diff` key of
  another mode is a config error, never silently ignored. Unknown keys are rejected.
- **Priority:** the `tolerance` of a call beats the rule, which beats exact; `textTolerance` beats
  `text_tolerance`. The masks of the rule are added to the call's `ignoreRegions`.
- **`fallback_platform`** applies to every golden of the workspace. It takes OS and architecture
  under the names a process reports (`macos-aarch64`, `linux-x86_64`, `linux-aarch64`,
  `windows-x86_64`; `macos-arm64`, `linux-x64` and `darwin` read as them).
- **`exclude`** is the opt-out: such a golden compares exactly, its text as pixels, and is written
  without a stamp, as Flutter does. A golden that no rule matches compares exactly too, but is
  stamped and tracked.
- Golden paths must be valid gleon test names (`[a-z0-9_.-]` segments, without case). An invalid
  config or name fails the test with the file path and the reason.
- `required_version`, `platform` and the `GLEON_PLATFORM` / `GLEON_FALLBACK_PLATFORM` variables
  belong to the CLI; the package checks only their syntax or ignores them.

</details>

## Metrics

A failing golden that a rule covers keeps its `golden.png`, `candidate.png` and `diff.png` in
`.gleon/runs/latest/artifacts/<platform>/<test name>/`, and a case report in
`.gleon/runs/latest/cases/<platform>/`; the failure message names the report. Both go away when the
golden passes again. Git ignores `.gleon/runs/`.

With metrics on, every comparison writes a case report and prints one line, so you can set
tolerances from measurements:

```text
gleon ✓ test/goldens/swatch.png  ssim 0.931 (≥0.800, +0.131)  color 5.2 (≤8, +2.8)  12 ms
```

Turn them on with `metrics: {enabled: true}` in `.gleon/gleon.yaml` or with `GLEON_METRICS=1`.

<details>
<summary>Case reports, run ids and the artifacts directory</summary>

- `GLEON_METRICS` beats the file: `1`/`true` on, `0`/`false` off (any case), empty is unset, any
  other value fails every golden. `metrics: {console: false}` keeps the files and drops the lines.
- A case report holds the SHA-256 and size of golden and candidate, the platform of the golden's
  stamp, the tolerance and masks, the outcome (`identical`, `match`, `mismatch`,
  `dimension_mismatch`, `error`, `updated`, `missing`), the metrics with their headroom to each
  threshold, the failure images, the test name, platform, Flutter version and timings. The JSON
  Schema is `gleon-model/schema/case.v5.json` in the gleon repository, shared with the CLI.
- Each test file runs in its own process, so reports of one run stay until overwritten. Set
  `GLEON_RUN_ID` (for example `${{ github.run_id }}-${{ github.run_attempt }}`; letters, digits,
  `.`, `_` and `-`, up to 128) to stamp the reports of a run with one id.
- `artifacts:` or `GLEON_ARTIFACTS_DIR` (which beats the file) can name another directory under
  `.gleon/runs/` outside `latest/`; any other value fails every golden. Platforms that share a
  workspace (a Mac and a Linux container on one checkout) never overwrite each other's images or
  reports. To keep them on a RAM disk, link `.gleon/runs` there.
- A report that cannot be written prints a warning and never fails the test. A golden that cannot
  be read or written is recorded as an `io` error.

</details>

## The gleon CLI (optional)

`flutter test` runs each test file in its own process, so it cannot sum up a run. The
[gleon CLI](https://github.com/gleon-rs/gleon) reads the same workspace and case reports, and
adds:

- the totals of a run and one line per failure, at the end of the test output;
- an HTML report with each failing golden, its candidate and diff side by side;
- in CI, a PR comment with the failures, and a `/gleon approve` comment that commits the new
  goldens to the PR branch.

```bash
gleon init                       # next to pubspec.yaml; keeps an existing .gleon/gleon.yaml
gleon test -- flutter test       # the tests as one run, summed up at the end
gleon report html --out .gleon/runs/latest/report.html
gleon approve                    # writes the failed candidates over their goldens
```

You do not need the CLI to use this package. It is licensed under the Business Source License
1.1: free for individuals, hobbyists, non-commercial open-source repositories and local
development, and free for all users until December 31, 2026 (see its
[license](https://github.com/gleon-rs/gleon#-license)). The
[gleon Action](https://github.com/gleon-rs/gleon#-cicd-integration-github-actions) runs it in
GitHub Actions.

## Golden harnesses

Harnesses that build golden scenes (alchemist, golden_toolkit, golden_screenshot, …) call
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

Tolerances and masks then come from `.gleon/gleon.yaml`. A comparator gets PNG bytes without text
boxes, so with real fonts its goldens fail on other operating systems. Where you can, match the
widget with gleon's `matchesGoldenFile`. alchemist can do that: see
[doc/alchemist.md](doc/alchemist.md).

<details>
<summary>Comparator details</summary>

- Goldens stay where they are: a `LocalFileComparator` subclass keeps naming them through its
  `getTestUri`. Installing twice keeps the first. Failures and `--update-goldens` behave as with
  gleon's matcher.
- The best path is a widget (`Finder`) through gleon's `matchesGoldenFile`: its raw pixels with
  the boxes of its text, and no PNG encoding. A `ui.Image` or PNG bytes through gleon's matcher,
  and everything through `GleonFileComparator`, are best effort: the same engine and rules,
  without text boxes.
- Through `GleonFileComparator`, `--update-goldens` on another OS than the golden's writes it over
  even with a `fallback_platform`, because the comparator sees no text to ignore.
- The `goldenFileComparator` assigned last wins. A harness that installs a tolerant comparator of
  its own (alchemist with `diffThreshold` above 0, golden_screenshot's default
  `allowedDiffPercent`, ff_golden with a non-strict tolerance) bypasses gleon or refuses to run:
  turn its threshold off and set the tolerance in `.gleon/gleon.yaml`.
- Text that a harness has already replaced in its image (alchemist's `obscureText`) cannot be
  compared.

</details>

## Performance

A widget golden from the captured frame to the verdict: Flutter encodes the frame as a PNG, gleon
compares its raw pixels and encodes a PNG only to keep a failure. Exact, no workspace; Apple M3
Max, Flutter 3.47.6, gleon 0.3.0, mean latency with
[bench_press](https://pub.dev/packages/bench_press):

| Scenario                                      | Golden    | Flutter SDK |   gleon | Speedup |
| --------------------------------------------- | --------- | ----------: | ------: | ------: |
| Passing                                       | 400x300   |     9.60 ms | 0.43 ms |     22x |
|                                               | 390x844   |     15.5 ms | 1.19 ms |     13x |
|                                               | 1170x2532 |     89.4 ms |  7.3 ms |     12x |
| Failing (small change, failure files written) | 400x300   |     43.7 ms |  1.9 ms |     23x |
|                                               | 390x844   |     77.5 ms |  4.2 ms |     18x |

<details>
<summary>Real text, PNG byte inputs and how the numbers were taken</summary>

Encoding the PNG is most of Flutter's cost. gleon's cost is reading the frame's pixels
(`toByteData`, which Flutter pays too) and decoding the golden; comparing is a `memcmp` per equal
row. The failing samples varied too much for bench_press to resolve a ratio, so their speedups are
ratios of means.

Finding the painted text of a widget adds time (measured with gleon 0.5.0): 0.6 ms for 50 lines
of text, 1.9 ms for a 1170x2532 screen of 1000 rows. 0.6 ms of text on top of the 0.43 ms of the
passing 400x300 golden would bring its 22x to about 9x.

One comparison of PNG bytes, Flutter's `LocalFileComparator` against gleon, with the same golden
and candidate, inside `flutter test` (mean latency; resolved ratios within ±8% at 95%
confidence):

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

Across the resolved cases gleon is 5.8x faster (geometric mean), and `ssim` costs no more than
exact. Flutter inverts both images and compares them pixel by pixel in Dart, and a failure renders
two diff images and encodes four PNGs; gleon decodes and compares in Rust and writes one diff
image.

</details>

## Known limitations

- `ssim` fails when glyphs move by half a pixel or more where it has no text boxes (byte and image
  inputs, text drawn on a canvas). It can pass a low-contrast color change of a one-pixel line:
  use `exact` or `pixel` where every pixel matters.
- `ssim` compares images up to 4096x4096 pixels. It does not record a larger golden and reports
  one as not comparable: use `exact` or `pixel` there.
- gleon's matcher needs `goldenFileComparator` to be a `LocalFileComparator` (Flutter's default,
  a subclass of it, or `GleonFileComparator`). Any other comparator fails with a message that
  names the ways out (see [Migrate](#migrate)).
- Web (`--platform chrome`) does not compile: the package uses `dart:ffi`. Keep web tests in
  files that import `flutter_test`, and run them apart.
- Linux needs the glibc of Ubuntu 26.04 or newer; musl (Alpine) and macOS x64 are not supported.
  On-device tests and app builds for Android, iOS and other targets get no native library, so
  `matchesGoldenFile` fails there with a message that says so.

<details>
<summary>Native library: where it comes from, and overrides</summary>

The package contains the native library of each supported host in `native/<target>/`. The build
hook takes the one of the test host; it never needs Rust or a network. The hook also runs for a
desktop debug `flutter run` of an app that has gleon in `dev_dependencies`: Flutter runs the hooks
of dev dependencies for every non-release build.

For a host without a prebuilt library, build one from a
[gleon](https://github.com/gleon-rs/gleon) checkout and point the package at it, in the app's
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    gleon:
      ffi_path: path/to/libgleon_ffi.so # use this library file as is
      # gleon_repo: ../gleon            # or build it from a gleon checkout
```

`ffi_path` wins over `gleon_repo`, which wins over the library of the package. Both must be
paths. A git dependency on this repository and the `release_url` user-define are described in
[CONTRIBUTING.md](CONTRIBUTING.md#git-dependencies-and-mirrors).

</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): architecture, checks, benchmarks and how the native
library is built and released.

## License

This package is MIT licensed (see `LICENSE`). Its native library is built from the gleon crates
`gleon-engine`, `gleon-model` and `gleon-ffi` (MIT OR Apache-2.0) and the third-party crates
listed with their license texts in [NATIVE_LICENSES.md](NATIVE_LICENSES.md).
