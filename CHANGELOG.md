## 0.3.0

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
- **Text tiles:** a text region thinner than a 16x16 tile, or clipped at the image edge, is judged
  as a whole tile (the rest of the square counts as equal): one differing pixel of a 4x1 strip is
  no longer a quarter of a tile. Case reports carry `policy_version` 3 for this.
- **Breaking:** native ABI 11 (`gleon_golden` takes its scalars as one struct and writes its
  summary to the caller's buffer; verdict code 0 is an error): libraries of 0.2.0 from
  `ffi_path`, `release_url` mirrors or `gleon_repo` checkouts are refused with the ABI message.
  Globs that would match differently than written, differently on Windows, or never, are config
  errors naming the pattern: `{a,b}` alternatives, `[^...]` (use `[!...]`), a class only `/`
  fits (`[/]`), `\`, `**` inside a segment (`a**`, `***`), a leading `/`, a `.`, `..` or empty
  segment (`./a`, `../a`, `a//b`), a trailing `/`, the empty pattern. `anti_alias` is no longer
  a config key.

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
