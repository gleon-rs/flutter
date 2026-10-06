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
  `.gleon/runs/latest/artifacts/`.
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
