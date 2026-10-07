// Targets share OS, arch and library file names by design.
// ignore_for_file: avoid-duplicate-constant-values

import 'dart:ffi' show Abi;

/// A host platform the `gleon-ffi` library is built and released for.
///
/// Plain Dart (no Flutter imports): used by `hook/build.dart`,
/// `bin/build_native.dart` and tests.
enum NativeTarget {
  /// Linux arm64 (Ubuntu 26.04+), e.g. Docker on Apple silicon.
  linuxArm64(
    os: 'linux',
    arch: 'arm64',
    rustTriple: 'aarch64-unknown-linux-gnu',
    libFileName: 'libgleon_ffi.so',
  ),

  /// Linux x64 (Ubuntu 26.04+).
  linuxX64(
    os: 'linux',
    arch: 'x64',
    rustTriple: 'x86_64-unknown-linux-gnu',
    libFileName: 'libgleon_ffi.so',
  ),

  /// Apple silicon Macs.
  macosArm64(
    os: 'macos',
    arch: 'arm64',
    rustTriple: 'aarch64-apple-darwin',
    libFileName: 'libgleon_ffi.dylib',
  ),

  /// Windows x64.
  windowsX64(
    os: 'windows',
    arch: 'x64',
    rustTriple: 'x86_64-pc-windows-msvc',
    libFileName: 'gleon_ffi.dll',
  );

  NativeTarget({
    required this.os,
    required this.arch,
    required this.rustTriple,
    required this.libFileName,
  });

  /// File in `native/` pinning the gleon commit that CI builds; the file of
  /// the same name inside `native/<target>/` records the commit a local build
  /// was made from.
  static const pinFileName = 'gleon_ref';

  /// Marks a build stamp whose checkout had uncommitted changes.
  static const dirtySuffix = '-dirty';

  /// Whether a local build stamped [builtFrom] (a gleon commit, with
  /// [dirtySuffix] when uncommitted changes were built too) may stand in for
  /// the [pinned] commit: only a build of that very commit may. A dirty build
  /// of it is how an unmerged engine change is tried out, so it is accepted;
  /// `bin/build_native.dart` makes one only with `--allow-dirty`.
  static bool isBuildOfPin(String? builtFrom, String pinned) =>
      builtFrom == pinned || builtFrom == '$pinned$dirtySuffix';

  /// Operating system, named like `code_assets`' `OS.name` and `dart:ffi`'s
  /// `Abi` (`macos`, `linux`, `windows`).
  final String os;

  /// CPU architecture, named like `Architecture.name` and `Abi` (`arm64`,
  /// `x64`).
  final String arch;

  /// Rust target triple the library is compiled for.
  final String rustTriple;

  /// File name cargo produces and the platform loader expects.
  final String libFileName;

  /// Stable identifier, e.g. `macos-arm64` (directory in `native/`).
  String get key => '$os-$arch';

  /// The name gleon gives this platform (Rust's `std::env::consts` names),
  /// e.g. `macos-aarch64`: the directory of its own goldens beside the shared
  /// ones, and the `fallback_platform` that names it.
  String get gleonPlatform => switch (rustTriple.split('-')) {
    [final rustArch, ...] => '$os-$rustArch',
    _ => key,
  };

  /// Flat, unique file name of this target's GitHub Release asset, e.g.
  /// `libgleon_ffi-macos-arm64.dylib`.
  String get assetName =>
      libFileName.replaceFirst(RegExp(r'\.(?=[^.]*$)'), '-$key.');

  /// Environment overrides for `cargo build` of this target, given the
  /// [parent] environment.
  ///
  /// Windows libraries link the C runtime statically, so they load without the
  /// Visual C++ redistributable. Cargo takes rustflags from one source only
  /// (`CARGO_ENCODED_RUSTFLAGS`, else `RUSTFLAGS`, else the target's, else
  /// `build.rustflags`), so the flag is appended to whichever takes effect;
  /// the build's flags move to the target's, which beats them.
  Map<String, String> cargoEnvironment(Map<String, String> parent) {
    if (os != windowsX64.os) return const {};
    const flag = '-C target-feature=+crt-static';
    if (parent['CARGO_ENCODED_RUSTFLAGS'] case final encoded?) {
      final encodedFlags = [
        if (encoded.isNotEmpty) encoded,
        ...flag.split(' '),
      ];

      return {'CARGO_ENCODED_RUSTFLAGS': encodedFlags.join('\x1f')};
    }
    if (parent['RUSTFLAGS'] case final rustflags?) {
      return {'RUSTFLAGS': '$rustflags $flag'.trim()};
    }
    final triple = rustTriple.toUpperCase().replaceAll('-', '_');
    final targetFlags = 'CARGO_TARGET_${triple}_RUSTFLAGS';
    final inherited = parent[targetFlags] ?? parent['CARGO_BUILD_RUSTFLAGS'];

    return {
      targetFlags: [?inherited, flag].join(' ').trim(),
    };
  }

  /// The `cargo` subcommand that builds this target on a host running
  /// [hostOs] (`Platform.operatingSystem`) whose target is [host], or null
  /// when that host cannot: plain cargo within one OS, the cross-linking
  /// wrappers for Linux (`cargo zigbuild`) or Windows (`cargo xwin`) targets
  /// built elsewhere; the macOS SDK only exists on macOS.
  List<String>? cargoSubcommand({
    required String hostOs,
    required NativeTarget? host,
  }) => switch (this) {
    _ when this == host => const ['build'],
    macosArm64 => hostOs == os ? const ['build'] : null,
    windowsX64 => hostOs == os ? const ['build'] : const ['xwin', 'build'],
    linuxArm64 || linuxX64 => const ['zigbuild'],
  };

  /// Whether a host running [hostOs] whose target is [host] can build this
  /// target (see [cargoSubcommand]).
  bool isBuildableOn({required String hostOs, required NativeTarget? host}) =>
      cargoSubcommand(hostOs: hostOs, host: host) != null;

  /// The targets named by [requested] keys (`host`, `all` or a target key),
  /// without duplicates, in order; `all` is every target this host can
  /// build (see [cargoSubcommand]).
  ///
  /// Throws a [FormatException] for an unknown key, `host` on an unsupported
  /// host, or a target this host cannot build, before anything is built.
  static List<NativeTarget> resolveKeys(
    List<String> requested, {
    required String hostOs,
    required NativeTarget? host,
  }) {
    final targets = <NativeTarget>{
      for (final key in requested)
        ...switch (key) {
          'all' => values.where(
            (target) => target.isBuildableOn(hostOs: hostOs, host: host),
          ),
          'host' => [
            host ??
                (throw FormatException(
                  'this host is not a supported target ($keys).',
                )),
          ],
          _ => [
            byKey(key) ??
                (throw FormatException(
                  'unknown target $key (expected host, all, $keys).',
                )),
          ],
        },
    };
    for (final target in targets) {
      if (!target.isBuildableOn(hostOs: hostOs, host: host)) {
        throw FormatException(
          '${target.key} can only be built on ${target.os}.',
        );
      }
    }

    return targets.toList();
  }

  /// All target keys, comma-separated (for messages).
  static String get keys => values.map((target) => target.key).join(', ');

  /// The target the hooks runner asks for, or null when it has no library:
  /// [os] and [arch] are the names of `code_assets`' `OS` and `Architecture`.
  ///
  /// Flutter runs the build hooks of dev_dependencies for every non-release
  /// build, so an app built for a device (Android, iOS) asks too: it gets no
  /// library instead of a failing build.
  static NativeTarget? requested(String os, String arch) => byKey('$os-$arch');

  /// Looks up a target by [key] (`<os>-<arch>`), or returns null.
  static NativeTarget? byKey(String key) =>
      values.where((target) => target.key == key).firstOrNull;

  /// The target of the running process, or null: [Abi] names are
  /// `<os>_<arch>`, like [key] with an underscore.
  static NativeTarget? get host =>
      byKey(Abi.current().toString().replaceAll('_', '-'));
}
