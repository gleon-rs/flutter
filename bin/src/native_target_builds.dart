/// What `bin/build_native.dart` builds where. Only `dart:*` and this package
/// may be imported here (see `build_native.dart`).
library;

import 'package:gleon/src/core/hook/native_target.dart';

/// What `bin/build_native.dart` builds where: maintainer tooling, kept out of
/// the published library.
extension NativeTargetBuilds on NativeTarget {
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
    .macosArm64 => hostOs == os ? const ['build'] : null,
    .windowsX64 => hostOs == os ? const ['build'] : const ['xwin', 'build'],
    .linuxArm64 || .linuxX64 => const ['zigbuild'],
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
          'all' => NativeTarget.values.where(
            (target) => target.isBuildableOn(hostOs: hostOs, host: host),
          ),
          'host' => [
            host ??
                (throw FormatException(
                  'this host is not a supported target (${NativeTarget.keys}).',
                )),
          ],
          _ => [
            NativeTarget.byKey(key) ??
                (throw FormatException(
                  'unknown target $key (expected host, all, '
                  '${NativeTarget.keys}).',
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
}
