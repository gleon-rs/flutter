## 0.6.0

- **The gleon CLI reads your workspace as it is.** `gleon init` of the CLI writes
  `baselines: goldens` into `.gleon/gleon.yaml`: the goldens next to the tests are the baselines,
  so the CLI sums up and reports the runs of `gleon test -- flutter test` and commits approved
  candidates over the goldens, but never scans them as screenshots. This version accepts the key
  (older ones reject it as unknown); it changes nothing in how goldens compare.
- README: an optional section on what the CLI adds (run summary, HTML report, PR comment,
  `/gleon approve` from CI) and how to start. Without the CLI the package works as before.
- The native library is built from the gleon commit that adds the key; `NATIVE_LICENSES.md`
  follows its dependency updates.
- **Text regions:** lines of a paragraph are told apart by their full height, so dense lines
  (a `height` below 1 with mixed sizes) keep a region each instead of merging; a clip that a
  perspective sends to infinity no longer breaks finding the text.
- **`loadAppFonts` is cheaper per test file:** a font file listed under several weights is
  loaded once, and the font checksum is updated from the changed bytes instead of reading the
  whole font.
- README: goldens compared through `GleonFileComparator` see no text, so with real fonts they
  fail on other operating systems and `--update-goldens` there writes them over.
- Contributors: a `gleon_repo` checkout reached through a symbolic link keeps tracking its
  sources.

## 0.5.0

- **Real text works without a config.** `--update-goldens` stamps every golden it writes with
  the platform (`gleon:platform`), with or without `.gleon/gleon.yaml` and whether or not a rule
  matches it (only a golden the workspace `exclude`s is written and compared as Flutter does, its
  text as pixels like the rest); an
  unstamped golden of the same image is written once more to stamp it. The stamp alone decides
  where text is compared: strictly (0.05 of a tile) on that platform, ignored elsewhere. A pass
  that ignored differing text because the golden names no platform (recorded by Flutter, or
  before this version, without a `fallback_platform`) says so once per test process.
- **`--update-goldens` always wins without a `fallback_platform`.** In a workspace with a
  `fallback_platform` (the platform that records it again), a golden recorded on another platform
  is kept while just its text differs; kept goldens print one line naming it. Without one,
  nothing could record the golden again, so it is written over.
- **Breaking: `mode` is required in `.gleon/gleon.yaml` rules, and `mode: exact` exists.** A rule
  without a mode used to tolerate 1% of the pixels silently (`pixel`'s default); `exact` compares
  every pixel and refuses `diff` keys. A `diff` key of another mode is an error even at its
  default (the full `diff` blocks of older `gleon init` configs keep the keys of their mode
  only). `required_version` and `screenshots` are optional: a
  workspace may name only its `fallback_platform`. `fallback_platform` applies to every golden of
  the workspace, matched by a rule or not.
- **Breaking: a `pixel` tolerance names its threshold.** `GoldenTolerance.pixel` requires
  `maxDiffRatio`, and a `mode: pixel` rule requires `diff.threshold` (0 for none): neither
  tolerates 1% of the pixels silently any more (write `maxDiffRatio: 0.01` /
  `threshold: 0.01` for the old behavior). The constructors of `ExactTolerance`,
  `PixelTolerance` and `SsimTolerance` are private: the factories of `GoldenTolerance` are the one
  way to create a tolerance, while the variants stay public for their fields and `switch`.
- **Failures say what to open and what to run.** A failure names its diff image
  (`<name>_gleonDiff.png`) next to the failures directory, a missing golden adds
  `flutter test --update-goldens`, and the box of an `ssim` failure is its "failing area" (the
  neighborhoods below the thresholds, as in the HTML report), no longer "changed area".
- **Platform names:** `macos-arm64`, `linux-x64`, `amd64` and `darwin` (the names of the release
  assets and of Dart's `Abi`) are read as `macos-aarch64`, `linux-x86_64` and `macos` wherever a
  platform is parsed (the config, the CLI's `--platform`, `--os`/`--arch` and variables); a
  custom key such as `custom-arm64` keeps its spelling.
- **The workspace search stops at the repository root** (the first directory with `.git`, `.hg`,
  `.jj` or `.sl`) and never takes the home directory or a directory above it unless that is a
  repository root itself: a `~/.gleon/gleon.yaml` no longer applies to projects without one. The
  gleon CLI searches the same way (its `.env` included).
- **Failures of a golden covered by a rule name their case report** (its absolute path: the test
  may run in a package below the workspace root) and `gleon report html`; the tip about
  `.gleon/gleon.yaml` is shown only without a rule.
- **A library the host cannot load** (an older glibc, musl) is reported as such, with the floor
  of the released Linux libraries (Ubuntu 26.04) and the ways out, instead of the advice for
  device builds.
- `gleon init` of the CLI writes a Flutter template next to a `pubspec.yaml` (`**/test/**/*.png`
  for the packages of a pub workspace too, `mode: exact`, `exclude: "**/failures/**"`,
  `fallback_platform` = the OS and architecture of the run); `--generic` and `--flutter` choose
  explicitly, and an existing config is kept. Like `git init` it initializes the directory it
  runs in (a package of a monorepo gets a nested workspace, named as such). A rule without
  `mode` names the modes in its error.
- Package metadata: `test_api` accepts every 0.x the SDK pins (a caret would break `pub get` on
  the next minor), pub.dev topics `testing` and `flutter-test`. `GleonFileComparator.withSession`
  (a test seam) is gone from the public API.
- **Only painted text is text.** Text laid out but not painted (the hidden pages of an
  `IndexedStack`, `Visibility.maintain`, `SliverOffstage`, a zero `SliverOpacity`, a route under
  an opaque one) no longer gets a text region, which hid the changes painted under it (text is
  ignored on other platforms by default). The painted text is found by replaying the paint of the
  capture without drawing or touching its layers, after the image is captured.
- **The build hook runs only when an input changes.** It declared files that may not exist (the
  bundled library, the pins), which the hooks runner takes for files modified during the build:
  every `flutter test` of a git or pub.dev dependency ran the hook again and printed "File
  modified during build. Build must be rerun.".
- Hook failures are reported as hook errors (the message, not an unhandled `Bad state` with its
  stack trace; network failures as infrastructure failures); HTTP 408 and 429 are retried; the
  user and password of any URL never appear in messages; a `release_url` on this machine (any
  loopback address) bypasses proxies; an `ffi_path` to the library of another OS is refused at
  once, whatever the case of its extension.
- **Downloads give up on silence, not on slowness.** A download fails (and is retried) after a
  minute without data instead of three minutes in all, so a slow connection finishes; a body
  larger than any library (64 MiB) is refused.
- **A git dependency between releases gets the engine it pins or a clear failure.** Releases
  name the gleon commit their libraries were built from (`gleon_ref.txt`, in the checksum list);
  a checkout pinning another commit (`ref: main` after an engine change) fails the build and
  names the tag to depend on, instead of loading an engine it was not made for. Releases without
  the file are not checked; the pub.dev archive has no pin.
- A `gleon_repo` build runs again only when a file it compiled (cargo's dep-info) or a manifest
  or `Cargo.lock` changes, not any file of the checkout (every input without a dep-info of
  absolute paths).
- A library file removed after the build is reported as missing, not as one this host cannot
  load; a library that is there but lacks a library it needs is reported as one this host cannot
  load.
- `loadAppFonts()` awaited in a test body (where it cannot finish) no longer breaks later calls;
  `await tester.runAsync(loadAppFonts)` is the way there. Concurrent calls share one load, and a
  failed load is started again by the next call.
- The alchemist integration moved to `doc/alchemist.md`; maintainer notes to `CONTRIBUTING.md`.
- Needs the gleon commit `native/gleon_ref` pins (ABI 13 and case reports v5 unchanged).

## 0.4.0

- **Breaking: no per-platform golden folders.** The package no longer reads or writes
  `goldens/<os>-<arch>/`: every platform compares the goldens next to the tests, as in Flutter.
  Folders written by 0.3.0 are ignored; delete them.
- **Goldens name the platform they were recorded on.** `--update-goldens` stamps each golden with
  its platform in a PNG text chunk (`gleon:platform`, ignored by decoders). Its text is compared
  there (0.05 of a tile) and ignored elsewhere, with or without `fallback_platform`; a golden
  without the stamp counts as recorded on `fallback_platform`. A failure names the platform the
  golden was recorded on.
- **`--update-goldens` works on every platform.** A golden recorded on another platform stays
  while only its text differs (no flip-flop between operating systems over their glyphs) and is
  written, stamped, when anything else changes; alchemist's forced updates behave the same.
- **`fallback_platform` is the canonical platform.** It warns about goldens recorded elsewhere,
  `--update-goldens` there records them again, and `GLEON_REQUIRE_CANONICAL=1` makes it compare
  them as its own (for its CI job). `gleon approve` stamps the goldens it writes with the platform
  of their case and prefers the `fallback_platform`'s candidate when several platforms offer one.
- **Breaking: case reports v5.** `golden.platform` names the stamp; `golden.fallback` is gone.
  Native ABI 13 (the `GLEON_REQUIRE_CANONICAL` session value).
- `bin/check_cases.dart` takes `--fallback-platform` only (`--own` is gone) and fails on goldens
  recorded on another platform.

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
  4.46 → 0.86 ms per passing golden against alchemist's default assertion.
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
