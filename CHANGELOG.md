## 0.3.0

- **Half the native library:** 0.97 MB instead of 1.88 MB on macOS arm64 (similar on Linux and
  Windows). Globs of `.gleon/gleon.yaml` match with the small `glob` crate instead of the regex
  engine of `globset`, and the engine runs on the calling thread instead of a thread pool per test
  process.
- **Faster comparisons:** a passing golden is one native call; widget and image captures are
  compared without a copy of their pixels; equal rows and equal frames take one `memcmp`; the
  golden is decoded without a copy. 20-37% less native time per golden in the package's
  measurements (`gleon-model/tests/perf.rs` of the gleon repository).
- **Breaking:** native ABI 11 (`gleon_golden` takes its scalars as one struct and writes its
  summary to the caller's buffer): libraries of 0.2.0 from `ffi_path`, `release_url` mirrors or
  `gleon_repo` checkouts are refused with the ABI message. Glob patterns with `{a,b}`
  alternatives, `**` inside a segment (`a**`) or a trailing `/` are config errors instead of
  matching differently than written.

## 0.2.0

The first pub.dev release.

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
