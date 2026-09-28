// Targets share OS, arch and library file names by design.
// ignore_for_file: avoid-duplicate-constant-values

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

  /// File in `native/` pinning the gleon commit that CI builds; a copy inside
  /// `native/<target>/` records which pin a local build was made for.
  static const pinFileName = 'gleon_ref';

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

  /// Flat, unique file name of this target's GitHub Release asset, e.g.
  /// `libgleon_ffi-macos-arm64.dylib`.
  String get assetName =>
      libFileName.replaceFirst(RegExp(r'\.(?=[^.]*$)'), '-$key.');

  /// Environment overrides for `cargo build` of this target, given the
  /// [parent] environment.
  ///
  /// Windows libraries link the C runtime statically, so they load without the
  /// Visual C++ redistributable. Cargo ignores per-target rustflags whenever
  /// `CARGO_ENCODED_RUSTFLAGS` or `RUSTFLAGS` is set, so the flag is appended
  /// to whichever of those takes effect.
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

    return {'CARGO_TARGET_${triple}_RUSTFLAGS': flag};
  }

  /// All target keys, comma-separated (for messages).
  static String get keys => values.map((target) => target.key).join(', ');

  /// Looks up a target by [key] (`<os>-<arch>`), or returns null.
  static NativeTarget? byKey(String key) {
    for (final target in values) {
      if (target.key == key) return target;
    }

    return null;
  }
}
