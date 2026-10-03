## 0.2.0 (unreleased)

- Real text in goldens, one golden for every OS: `loadAppFonts()` loads the app's fonts and Roboto
  (with line metrics aligned across operating systems). The text of a widget (its lines from the
  render tree) never fails by default, because operating systems rasterize glyphs differently;
  everything else is compared exactly. `textTolerance` (0.0–1.0, or `text_tolerance` of a
  `.gleon/gleon.yaml` pixel rule) lowers that: the largest share of differing pixels in any 16x16
  square of text. A `textTolerance` that cannot apply (an SSIM rule, a byte input) warns.
- A widget is captured and compared as raw pixels (native ABI 9): no PNG is encoded unless the
  golden fails. Its case reports are `match` (not `identical`) and have no candidate hash on a
  pass; masks no longer count towards the compared pixels in pixel mode.
- The native engine does the whole job of a golden in one call: it resolves the
  rule, compares, and writes failure artifacts, case reports and `--update-goldens` goldens
  itself; the package passes facts and gets back a verdict, an error kind and the texts.
- Each golden belongs to the nearest directory above it with `.gleon/gleon.yaml`, not to the
  working directory; one run may span several workspaces, and an edited config is read again.
- **Breaking:** case reports move to schema version 2 (`case.v2.json` of the gleon repository), the
  one result format of the gleon CLI and its integrations: `artifacts` (paths of the failure
  images), `error_kind` for errors, `max_excess` in SSIM metrics, `run_id` and `golden.blob`.
- A failing golden covered by a rule keeps its golden, candidate and diff in the artifacts
  directory (`.gleon/runs/latest/artifacts/<test name>/` by default, `artifacts:` in
  `.gleon/gleon.yaml` or `GLEON_ARTIFACTS_DIR` to move it under `.gleon/runs/`); a missing golden
  keeps its candidate, and a pass removes the images of an earlier failure. `failures/` next to
  the test is written as before.
- The gleon CLI turns the case reports of a `flutter test` run into a PR comment, HTML and JUnit
  reports, the run history and approvals (`gleon test -- flutter test`, then `gleon report`,
  `gleon dashboard` or `gleon approve`); see the README.
- A failing golden covered by a rule writes its case report without metrics too (metrics add the
  reports of passes and the console line), so `gleon approve` works after a plain `flutter test`;
  a pass removes the report of an earlier failure.
- `GLEON_RUN_ID` stamps every case report of a run with the same id. Like `GLEON_METRICS`, an
  invalid `GLEON_RUN_ID` or `GLEON_ARTIFACTS_DIR` fails every golden. A golden that cannot be read
  or written is recorded as an `io` error.
- Failures caused by a bug in gleon (a native panic or a broken contract) end with a request to
  report it; a missing native library (web, devices) fails with a message saying what provides it.
- `ignoreRegions` beyond 4294967295 pixels throw an `ArgumentError` instead of wrapping around.
- Several warnings of one comparison print one line each.
- A match abandoned by a timed-out test puts Flutter's `goldenFileComparator` back when the test
  ends, and a match that cannot register its clean-up never blocks later matches.
- Numbers in messages, console lines and matcher descriptions are rounded to at most four
  decimals (`0.0167%`, `ssim ≥ 0.9995`); a positive threshold too small to show reads `<0.0001%`.
- `GLEON_METRICS` is read by the native engine and validated the same way with or without a
  workspace (an invalid value fails every golden). An invalid `.gleon/gleon.yaml` now also fails a
  missing golden inside the workspace.
- Missing goldens are recorded as `missing` case reports; a case report that cannot be written is
  a warning instead of a failure.
- Case reports and failure artifacts are written atomically without flushing to disk (a flush
  costs about 5 ms per file on macOS); goldens stay durable, and `--update-goldens` leaves
  unchanged goldens untouched. A failure without a diff image removes the stale diff of an earlier
  failure. Masks reaching beyond the image are reported as a warning, byte-identical goldens
  included.
- The example's tolerance is calibrated on the CI metrics of every host (`min_similarity` 0.73,
  `color_tolerance` 46 instead of the guessed 0.6 and 64).
- Local native builds record the gleon commit they were made from; the hook accepts them only for
  the pinned commit. `bin/build_native.dart` refuses a checkout git cannot read, and one with
  uncommitted changes to the library's sources unless `--allow-dirty` is passed.
- Downloads drop a connection whose body stalls before retrying; the hook keeps a cached file it
  cannot replace on Windows only when it has exactly the downloaded content.
- Benchmarks (`benchmark/`, bench_press): one golden comparison through Flutter's own comparator
  against gleon; gleon is 5-18x faster (7.7x geometric mean) inside `flutter test`, see the
  README's Performance section.
- Internal: the FFI bindings and C types live in one file; the build hook's atomic writes moved to
  `lib/src/core/hook/`; tests give the engine its environment (`GleonEnvironment`) instead of
  depending on the shell.

## 0.1.0

- **Breaking:** `matchesGoldenFile(key, {version, tolerance, ignoreRegions})` takes a sealed
  `GoldenTolerance` (`.exact()`, `.pixel(maxDiffRatio:)`, `.ssim(minSimilarity:, colorTolerance:)`)
  instead of `mode`/`threshold`/`minSimilarity`/`colorTolerance`; a parameter of another mode can
  no longer be written. `GoldenMode`, `GleonGoldenConfig` and `gleonGoldenDefaults` are removed,
  and `GleonGoldenComparator`, `GleonMatchesGoldenFile` and `PixelRegion` are no longer public.
- Suite settings come from the gleon CLI's `.gleon/gleon.yaml`: per-path tolerance rules
  (the first matching rule wins, a call's `tolerance` overrides it) and masks, resolved by the
  CLI's own code; invalid configs and golden names fail with the parser's message.
- Opt-in metrics (`metrics: {enabled: true}` or `GLEON_METRICS=1`): a JSON case report per golden
  in `.gleon/runs/latest/cases/` (schema `case.v1.json` of the gleon repository) with the headroom
  to each threshold, plus one console line per golden. Passing comparisons report metrics too.
- Native ABI 4 (`gleon_config_resolve`, metrics and timings in every comparison report).
- Internal restructuring into a Flutter-free core (`lib/src/core/`) and a Flutter layer.
- `gleon_repo` source builds re-run when any crate the library depends on changes (found through
  `path` dependencies, so new engine crates are tracked automatically).
- Strict analysis (analyzer lints and DCM presets) and CI quality gates; the example records
  metrics on every CI host (`metrics-<target>` artifacts).

## 0.0.1

- `matchesGoldenFile` drop-in with `exact`, `pixel` and `ssim` modes and ignore regions.
- Native library delivered through GitHub Releases (macOS arm64, Linux x64/arm64, Windows x64),
  verified by SHA-256 and cached by the build hook.
