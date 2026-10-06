## 0.2.0 (unreleased)

The first pub.dev release; changes since the git-only 0.0.1.

- **Breaking:** `matchesGoldenFile(key, {version, tolerance, ignoreRegions, textTolerance})` takes
  a sealed `GoldenTolerance` (`.exact()`, `.pixel(maxDiffRatio:)`,
  `.ssim(minSimilarity:, colorTolerance:)`) instead of `mode`/`threshold`/`minSimilarity`/
  `colorTolerance`; a parameter of another mode can no longer be written. `GoldenMode`,
  `GleonGoldenConfig` and `gleonGoldenDefaults` are removed, and `GleonGoldenComparator`,
  `GleonMatchesGoldenFile` and `PixelRegion` are no longer public.
- Real text in goldens: `loadAppFonts()` loads the app's fonts and Roboto (with line metrics
  aligned across operating systems), and the text of a widget (its lines from the render tree) is
  judged by `textTolerance` (0.0–1.0, or `text_tolerance` of a `.gleon/gleon.yaml` pixel rule):
  the largest share of differing pixels in any 16x16 square of text; everything else is compared
  exactly. A `textTolerance` that cannot apply (an SSIM rule, a byte or image input) warns.
- Platform-aware goldens: `fallback_platform` in `.gleon/gleon.yaml` names the platform the
  goldens are recorded on, where their text is compared; other platforms keep their own goldens
  in `goldens/<os>-<arch>/` and fall back to the shared ones with text ignored. See the README's
  "Real text".
- Suite settings come from `.gleon/gleon.yaml`, the gleon CLI's workspace file: per-path
  tolerance rules (the first matching rule wins, a call's `tolerance` overrides it) and masks,
  resolved by the CLI's own code; invalid configs and golden names fail with the parser's
  message. Each golden belongs to the nearest directory above it with that file (one run may span
  several workspaces), and an edited config is read again.
- Opt-in metrics (`metrics: {enabled: true}` or `GLEON_METRICS=1`): a JSON case report per golden
  in `.gleon/runs/latest/cases/` (schema `case.v2.json` of the gleon repository) with the headroom
  to each threshold, plus one console line per golden. Failing goldens covered by a rule are
  recorded without metrics too, and keep their golden, candidate and diff in the artifacts
  directory (`.gleon/runs/latest/artifacts/<test name>/`, or `artifacts:` /
  `GLEON_ARTIFACTS_DIR`); a pass removes them. `GLEON_RUN_ID` stamps the reports of a run. An
  invalid `GLEON_METRICS`, `GLEON_RUN_ID` or `GLEON_ARTIFACTS_DIR` fails every golden.
- Widgets and `ui.Image` inputs are compared as raw pixels: a PNG is encoded only to keep the
  candidate (case reports say `match`, not `identical`); gleon is 5-20x faster than Flutter's
  comparator inside `flutter test` (see the README's Performance section).
- Every input is matched with the match's own comparator and `--update-goldens` flag, read before
  its first await, and `goldenFileComparator` is never replaced: a match abandoned by a timed-out
  test never uses the next test's comparator. `--update-goldens` reports a failure to write any
  input's golden (an invalid config, a custom `goldenFileComparator`) as the test's failure
  message, like a comparison.
- The native engine does the whole job of a golden in one call (native ABI 10): it resolves the
  rule, compares, and writes failure artifacts, case reports and `--update-goldens` goldens
  itself. Goldens are written durably and only when changed; case reports and artifacts
  atomically. `GleonSession.dispose()` releases a native session at once.
- Failures caused by a bug in gleon end with a request to report it; a missing native library
  (web, devices) or a library of another version fails with a message saying what provides it.
  `ignoreRegions` beyond 4294967295 pixels throw an `ArgumentError`. Numbers in messages are
  rounded to at most four decimals; several warnings of one comparison print one line each.
- Build hook: the checksum list of a release is cached per URL and package version, so a
  `release_url` mirror kept across upgrades serves the new release, and a cached list that
  disagrees with a mirror's library is reloaded once; errors name `release_url`. Downloads drop
  a connection whose body stalls before retrying. Local native builds record the gleon commit
  they were made from and are accepted only for the pinned commit. `gleon_repo` builds keep a
  `CARGO_TARGET_<triple>_RUSTFLAGS` or `CARGO_BUILD_RUSTFLAGS` on Windows; the hook's logic lives
  in `lib/src/core/hook/` and is tested.
- `NATIVE_LICENSES.md` lists the crates linked into the native library with their license texts.
- Maintainers: `bin/build_native.dart --target all` builds every target the host can, checks them
  all before building, and writes each library atomically before its stamp;
  `bin/native_licenses.dart` regenerates the license file; `bin/check_cases.dart` lets CI prove
  where each golden of the example was compared.
- The example compares exactly, with real fonts and `fallback_platform: macos-aarch64`. Benchmarks
  (`benchmark/`, bench_press) compare Flutter's comparator with gleon.

## 0.0.1

- `matchesGoldenFile` drop-in with `exact`, `pixel` and `ssim` modes and ignore regions.
- Native library delivered through GitHub Releases (macOS arm64, Linux x64/arm64, Windows x64),
  verified by SHA-256 and cached by the build hook.
