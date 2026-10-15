# Contributing to gleon (Flutter)

The consumer-facing documentation is the [README](README.md); this page is for contributors and
maintainers of the package.

## Architecture

One package with a hard internal boundary:

```text
lib/gleon.dart            exports only (flutter_test minus matchesGoldenFile, plus the gleon API)
lib/alchemist.dart        exports only gleonAlchemistExpectation (alchemist's golden assertion)
lib/src/core/             plain Dart: never imports Flutter (dart:ui, package:flutter*)
  compare/                GoldenTolerance, PixelRegion (the call's tolerances,
                          masks and text regions)
  config/                 GleonIntegration (who calls), GleonSession (the native session)
  native/                 @Native leaf bindings, NativeEngine (ABI check, packing), verdicts,
                          error kinds
  hook/                   what hook/build.dart needs: NativeLibrary (which library, in which
                          order), UserDefines (hooks-free, so tests pass plain maps) and its
                          HookUserDefines adapter (imported by the hook only), native targets,
                          release download, source build, atomic writes
lib/src/flutter/          the Flutter layer: matchesGoldenFile, the widget capture and its text
                          regions, the comparator of a match, GleonFileComparator (for
                          harnesses) and alchemist's expectation, loadAppFonts, FlutterSession
                          (this package as an integration)
hook/build.dart           thin build hook on top of lib/src/core/hook/
bin/                      maintainer scripts (dart:*, crypto and this package only), run with
                          plain `dart`: build_native, native_licenses, check_cases (CI)
  src/                    their logic, tested in test/tooling/ (neither is published):
                          CaseCheck, LicenseCrate and NativeLicenses, NativeBuild (install,
                          checkout state), and the shared command line (cli.dart)
```

The native engine (`gleon-ffi`) does the whole job of a golden: it finds the workspace, resolves
the `.gleon/gleon.yaml` rule, reads and compares the golden, and writes failure artifacts, case
reports and updated goldens; this package passes facts (paths, the raw pixels or PNG, the call's
tolerance, masks and text regions) and shows the verdict and texts it gets back. The C types and bindings of that contract
live together in `lib/src/core/native/gleon_ffi.dart`.

**Rule:** code in `lib/src/core/` must not import Flutter, so it stays usable from `dart test`,
the build hook and other SDKs later; everything Flutter-specific (`Rect`, matchers, comparators)
lives in `lib/src/flutter/` and converts to core types at the boundary. DCM enforces the rule
(`avoid-banned-imports` in `analysis_options.yaml`).

## Why leaf FFI calls

Every native call is an `isLeaf: true` call. That allows passing the candidate zero-copy via
`Uint8List.address` (a call's strings as one UTF-8 buffer plus a `Uint32List` of their lengths,
its scalars as one `Struct.create`d struct) and letting the library write the verdict and
`{ptr, len}` text slices into another one, so the Dart side never allocates native memory (no
`package:ffi`, no `malloc`/`free` pairs; only the session is released by a `NativeFinalizer`, and
the texts of a failure by one more call). A passing golden is one native call.
The price is that the isolate group cannot reach a GC safepoint while a comparison runs
(milliseconds for typical goldens, seconds for very large SSIM comparisons). For tests that is the right trade-off: the test
awaits the result anyway, and `flutter test` parallelizes across processes. Apps that must stay
responsive would instead copy into `malloc`ed memory and make non-leaf calls in `Isolate.run`.

## Checks

```sh
dart format --set-exit-if-changed .
flutter analyze --fatal-infos     # also in example/
dcm analyze .                     # DCM 1.39.2, also in example/
flutter test                      # also in example/
dart bin/consumer_check.dart      # the package as a consumer meets it (see below)
```

`bin/consumer_check.dart` builds a fresh app with gleon as a dependency without `native/`, no Rust
on `PATH` and no `.gleon/gleon.yaml`: its build hook downloads the library of this host from a
local release served by the script (checksums verified), reuses it offline after a changed hook
input, then finds it bundled as in the pub.dev archive; `--update-goldens` stamps the app's golden
and a changed digit fails on this platform. CI runs it on macOS and Linux with
`--stray-home-config` (an invalid `~/.gleon/gleon.yaml`, which must change nothing). It needs
`native/<target>/` built first. The app gets the package without what `.pubignore` leaves out
at its top level (a test keeps the two in sync), `PATH` keeps Flutter but no directory holding
cargo, rustc or rustup, and the run fails if the hook built the library from source. Ctrl-C
stops its server and removes its temporary directories.

Case reports written by the tests are validated against `case.v5.json` of the pinned commit
(`native/gleon_ref`, read with `git show` whatever the checkout's own state) when a gleon checkout
that has that commit sits next to this repository (`../gleon`, as in CI); without it that check is
skipped.

`analysis_options.yaml` is the single, strict configuration (analyzer lints plus DCM presets);
every disabled or narrowed rule carries its reason.

## Benchmarks

`benchmark/` holds [bench_press](https://pub.dev/packages/bench_press) benchmarks that need the
Flutter engine (`dart:ui`), so they run under `flutter test`, not `dart run bench_press run`:

```sh
flutter test benchmark/      # ~3 min; results in build/benchmark/*.json
dart run bench_press report --from-json build/benchmark/golden_comparison.json
dart run bench_press report --from-json build/benchmark/widget_capture.json
```

To check a change for regressions, keep the JSON of a run before it and compare
(`dart run bench_press diff old.json build/benchmark/golden_comparison.json`). Run on an idle
machine: bench_press withholds ratios of unstable samples ("unresolved"). `BENCH_PRESS_ARGS`
passes options (`--validate` for a smoke run, as CI does; `--trials 30`). The manual
**Benchmark** workflow runs them on every supported host and puts the report into each job's
summary. `example/benchmark/` (run in `example/`) measures alchemist's default assertion against
gleon's for a passing golden of the example app (see [alchemist](#alchemist)).

## Maintainers

The native code (`gleon-engine`, `gleon-model`, `gleon-ffi`) lives in the
[gleon repository](https://github.com/gleon-rs/gleon); `native/gleon_ref` pins the commit CI builds.
Build the library for this machine into `native/<target>/` (the hook prefers it over downloading):

```sh
dart bin/build_native.dart                 # host; --target all: every target this host can
```

Use plain `dart`, not `dart run`: `dart run` executes the build hook first. `--target all` builds
all four targets on macOS and all but macOS elsewhere; Linux targets of another OS or
architecture need zig and `cargo-zigbuild` (`cargo install --locked cargo-zigbuild` on any host),
Windows from macOS or Linux `cargo-xwin`. CI builds every target natively. A library is replaced
atomically and stamped only after it; the `--dist` copy (release assets) comes last. A build
records the gleon commit it was made from, and the hook uses it only while `native/gleon_ref` pins
that commit. To try an unmerged engine change on top of the pinned commit, build with
`--allow-dirty` (and rebuild after every change: the hook cannot tell two dirty builds apart); to
test another checkout, use the `gleon_repo` user-define. That build runs inside Flutter's hooks
runner, which passes on only part of the environment: `RUSTFLAGS` and `RUSTC_WRAPPER` never
reach it, and `CARGO_*`/`RUSTUP_*` only from Flutter 3.49. Use `CARGO_BUILD_RUSTFLAGS` /
`CARGO_BUILD_RUSTC_WRAPPER` (Flutter 3.49+), a `.cargo/config.toml` in the checkout, or
`bin/build_native.dart`, which sees the whole environment.

`NATIVE_LICENSES.md` lists every crate linked into the library with its license texts and names
the pinned commit it was generated for. After moving `native/gleon_ref`, regenerate it (CI checks
it). The gleon repo must be at the pinned commit: its `git rev-parse HEAD` is checked; for a tree
exported without git, pass the commit with `--commit`. To leave your gleon checkout alone:

```sh
dart bin/native_licenses.dart              # --check: fail when it is stale
git -C ../gleon archive "$(cat native/gleon_ref)" | tar -x -C /tmp/gleon-pin
dart bin/native_licenses.dart --gleon-repo /tmp/gleon-pin --commit "$(cat native/gleon_ref)"
```

Releasing: bump `version` in `pubspec.yaml`, `FlutterSession.packageVersion` and `CHANGELOG.md`,
update `native/gleon_ref` (and `NATIVE_LICENSES.md`) if the engine changed, and push the tag
`vX.Y.Z`. The release workflow builds and tests all targets on
their own OS, attaches the libraries, `gleon_ref.txt` (the gleon commit they were built from,
which the hook of a git checkout compares with its pin) and `SHA256SUMS.txt` to a GitHub Release,
fails unless that release is immutable (enable it in the repository settings first), and then
verifies the download path on every OS.
