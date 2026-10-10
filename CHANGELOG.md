## 0.3.0

- **`GleonFileComparator` for golden harnesses:** installed once in
  `test/flutter_test_config.dart`, it compares the goldens of every test that calls
  `flutter_test`'s own `matchesGoldenFile` (alchemist, golden_toolkit, …) with the gleon engine
  and the rules of `.gleon/gleon.yaml`. A best-effort path (PNG bytes, text compared like every
  other pixel): gleon's matcher with a widget stays the fastest and the only one that compares
  real text right. `fromExisting` keeps the golden names of a `LocalFileComparator` subclass
  (its `getTestUri`) and returns an installed `GleonFileComparator` as is. gleon's matcher accepts
  any `LocalFileComparator` subclass (it only takes its golden directory; the subclass's threshold
  does not apply).
- **alchemist adapter:** `package:gleon/alchemist.dart`'s `gleonAlchemistExpectation()`, assigned
  to alchemist's `goldenFileExpectationFn`, compares every alchemist golden with gleon's matcher:
  the widget with the boxes of its text, no PNG encoded to compare, no dependency on alchemist.
  Failures of obscured text (alchemist's CI default) say how to compare real text, failures under
  a comparator's own threshold (alchemist's `diffThreshold`) that it does not apply. The example app runs it (one set of
  real-text goldens beside the others, alchemist's runner for the edge cases), with a benchmark:
  4.78 → 0.90 ms per passing golden against alchemist's default assertion.
- **Half the native library:** release libraries of about 1 MB instead of 2 MB (macOS arm64
  1.88 → 0.98 MB, Linux x64 2.21 → 1.13 MB, Linux arm64 1.97 → 1.00 MB). Globs of
  `.gleon/gleon.yaml` match with the small `glob` crate instead of the regex engine of `globset`,
  and the engine runs on the calling thread instead of a thread pool per test process.
- **Faster comparisons:** the engine reads widget and image captures in place instead of copying
  them, equal rows and frames take one `memcmp`, the golden is decoded without a copy, and a
  passing golden without a console line or warning is one native call. Native time per golden: passes
  12-42% less, failures 9-26% (`gleon-model/tests/perf.rs` of the gleon repository); byte inputs
  in `flutter test` 8-11% faster for re-encoded passes and 11-24% for failures, identical bytes
  unchanged (`bench_press diff` against 0.2.0 on one machine).
- **Pixel options:** `.pixel(channelTolerance:, antiAlias:, edgeThreshold:)` (yaml
  `channel_tolerance`, `anti_alias`, `edge_threshold`, for `mode: pixel` rules only), all off by
  default and never applied to text, let small channel deltas, anti-aliased pixels and pixels on
  the golden's edges count as equal (see the README's "Pixel options" for what each one hides).
  Values are 0–254. Case reports count them as `tolerated_pixels` and `edge_pixels`. A rule's
  diff keys of the other mode (`threshold` under `ssim`, `min_similarity`/`color_tolerance` under
  `pixel`) are config errors instead of being ignored.
- **Text under `ssim`:** `textTolerance` (and a rule's `text_tolerance`) works with `.ssim()`
  too: text is judged by its tiles and left out of both SSIM gates, so another OS's glyphs no
  longer fail an SSIM comparison of a widget. Text and masks are left out by taking the golden's
  pixels, so the pixels around them are compared as strictly as any other (they were painted
  black before, which hid color changes right next to a mask).
- **Diffs of every failure:** images of different sizes keep a diff image of both sizes (masked
  pixels unmarked); SSIM case reports list the `changed` and `failing` regions with their own
  metrics, which the gleon CLI's HTML report shows.
- **Text tiles:** a text region thinner than a 16x16 tile, or clipped at the image edge, is judged
  as a whole tile (the rest of the square counts as equal): one differing pixel of a 4x1 strip is
  no longer a quarter of a tile.
- **Breaking:** native ABI 12 (`gleon_golden` takes its scalars as one struct and writes its
  summary to the caller's buffer; verdict code 0 is an error): libraries of 0.2.0 from
  `ffi_path`, `release_url` mirrors or `gleon_repo` checkouts are refused with the ABI message.
  Case reports are schema 4 with `policy_version` 4 (text tiles and text under SSIM). A yaml
  `mode: pixel` rule without `threshold` allows 0.01 of the pixels (was 0.1), like `.pixel()`.
  Globs that would match differently than written, differently on Windows, or never, are config
  errors naming the pattern: `{a,b}` alternatives, `[^...]` (use `[!...]`), a class only `/`
  fits (`[/]`), `\`, `**` inside a segment (`a**`, `***`), a leading `/`, a `.`, `..` or empty
  segment (`./a`, `../a`, `a//b`), a trailing `/`, the empty pattern.

## 0.2.0

The first release (a git tag; pub.dev publishing is postponed).

- **Drop-in `matchesGoldenFile`:** replace the `flutter_test` import with
  `package:gleon/gleon.dart`; without extra parameters goldens behave like Flutter's (exact,
  resolved relative to the test file, rewritten by `flutter test --update-goldens`). Widgets,
  `ui.Image`s and PNG bytes are accepted, as in Flutter.
- **Tolerance:** `tolerance: GoldenTolerance` with `.exact()`, `.pixel(maxDiffRatio:)` or
  `.ssim(minSimilarity:, colorTolerance:)`, an SSIM comparison that tolerates rendering noise but
  still catches changed content, color changes and blur.
- **Ignore regions:** `ignoreRegions` excludes rectangles (clocks, animations) from any comparison.
- **Real text:** `loadAppFonts()` loads the app's fonts instead of Flutter's box font, and
  `textTolerance` bounds the share of differing pixels in any 16x16 square of text.
- **Platform-aware goldens:** `fallback_platform` names where the goldens are recorded; there
  text is compared, other platforms compare everything else and ignore text until they record
  their own goldens in `goldens/<os>-<arch>/`.
- **Suite rules in `.gleon/gleon.yaml`:** per-path tolerances and masks in the same workspace file
  as the gleon CLI.
- **Metrics and case reports:** opt-in (`GLEON_METRICS=1`) JSON case reports with the headroom to
  each threshold and a console line per golden, in the gleon CLI's result format; failing goldens
  keep their golden, candidate and diff images, in `failures/` next to the test and in
  `.gleon/runs/latest/artifacts/<platform>/`; platforms sharing a workspace keep their reports
  apart (`.gleon/runs/latest/cases/<platform>/`).
- **Fast:** 5-20x faster than Flutter's own comparator inside `flutter test` (see the README's
  "Performance").
- **No Rust needed:** `flutter test` on macOS arm64, Linux x64/arm64 (Ubuntu 26.04+) and
  Windows x64 with a prebuilt, checksum-verified native library; the `release_url` and `ffi_path`
  user-defines serve mirrors and offline machines.
- **Breaking since the git-only 0.0.1:** `mode`/`threshold`/`minSimilarity`/`colorTolerance`
  are replaced by `tolerance: GoldenTolerance`.

## 0.0.1

- `matchesGoldenFile` drop-in with `exact`, `pixel` and `ssim` modes and ignore regions.
- Native library delivered through GitHub Releases (macOS arm64, Linux x64/arm64, Windows x64),
  verified by SHA-256 and cached by the build hook.
