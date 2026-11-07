import 'package:gleon/src/core/hook/native_target.dart';

/// The platforms of the gleon engine.
extension GleonPlatform on NativeTarget {
  /// The name gleon gives this platform (Rust's `std::env::consts` names),
  /// e.g. `macos-aarch64`: the `fallback_platform` that names it.
  String get gleonPlatform => switch (rustTriple.split('-')) {
    [final rustArch, ...] => '$os-$rustArch',
    _ => key,
  };
}
