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
