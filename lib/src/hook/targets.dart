// Native targets shipped by this package. Plain Dart (no Flutter imports):
// used by `hook/build.dart`, `bin/build_native.dart` and tests.

/// File in `native/` pinning the gleon commit that CI builds; a copy inside
/// `native/<target>/` records which pin a local build was made for.
const pinFileName = 'gleon_ref';

/// A host platform the `gleon-ffi` library is built and released for.
enum NativeTarget {
  /// Apple silicon Macs.
  macosArm64('macos', 'arm64', 'aarch64-apple-darwin', 'libgleon_ffi.dylib'),

  /// Linux x64 (Ubuntu 26.04+).
  linuxX64('linux', 'x64', 'x86_64-unknown-linux-gnu', 'libgleon_ffi.so'),

  /// Linux arm64 (Ubuntu 26.04+), e.g. Docker on Apple silicon.
  linuxArm64('linux', 'arm64', 'aarch64-unknown-linux-gnu', 'libgleon_ffi.so'),

  /// Windows x64.
  windowsX64('windows', 'x64', 'x86_64-pc-windows-msvc', 'gleon_ffi.dll');

  const NativeTarget(this.os, this.arch, this.rustTriple, this.libFileName);

  /// Operating system, named like `code_assets`' `OS.name` and `dart:ffi`'s
  /// `Abi` (`macos`, `linux`, `windows`).
  final String os;

  /// CPU architecture, named like `Architecture.name` and `Abi` (`arm64`, `x64`).
  final String arch;

  /// Rust target triple the library is compiled for.
  final String rustTriple;

  /// File name cargo produces and the platform loader expects.
  final String libFileName;

  /// Stable identifier, e.g. `macos-arm64` (directory in `native/`).
  String get key => '$os-$arch';

  /// Flat, unique file name of this target's GitHub Release asset.
  String get assetName {
    final dot = libFileName.lastIndexOf('.');
    return '${libFileName.substring(0, dot)}-$key${libFileName.substring(dot)}';
  }

  /// Environment overrides for `cargo build` of this target, given the
  /// [parent] environment.
  ///
  /// Windows libraries link the C runtime statically, so they load without the
  /// Visual C++ redistributable. Cargo ignores per-target rustflags whenever
  /// `CARGO_ENCODED_RUSTFLAGS` or `RUSTFLAGS` is set, so the flag is appended
  /// to whichever of those takes effect.
  Map<String, String> cargoEnvironment(Map<String, String> parent) {
    if (os != 'windows') return const {};
    const flag = '-C target-feature=+crt-static';
    if (parent['CARGO_ENCODED_RUSTFLAGS'] case final encoded?) {
      final flags = [if (encoded.isNotEmpty) encoded, ...flag.split(' ')];
      return {'CARGO_ENCODED_RUSTFLAGS': flags.join('\x1f')};
    }
    if (parent['RUSTFLAGS'] case final flags?) {
      return {'RUSTFLAGS': '$flags $flag'.trim()};
    }
    final triple = rustTriple.toUpperCase().replaceAll('-', '_');
    return {'CARGO_TARGET_${triple}_RUSTFLAGS': flag};
  }

  /// Looks up a target by [key] (`<os>-<arch>`), or returns null.
  static NativeTarget? byKey(String key) {
    for (final target in values) {
      if (target.key == key) return target;
    }
    return null;
  }
}
