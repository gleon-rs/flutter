import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:hooks/hooks.dart';

import '../../hook/build.dart' as hook;

/// The wiring of `hook/build.dart` for the targets it supports: the asset id
/// that `@DefaultAsset` of `gleon_ffi.dart` loads, the link mode, and the
/// dependencies; validated by `package:code_assets` like the hooks runner
/// does (the library resolution itself: `native_library_test.dart`).
void main() {
  /// The single asset of the hook for [targetOS]-[targetArchitecture] with
  /// the `ffi_path` user-define set to [library], and the dependencies.
  Future<(CodeAsset, List<Uri>)> build(
    File library, {
    required OS targetOS,
    required Architecture targetArchitecture,
  }) async {
    final built = <(CodeAsset, List<Uri>)>[];
    await testCodeBuildHook(
      mainMethod: hook.main,
      check: (_, output) => built.add((
        output.assets.code.singleOrNull ?? fail('one asset expected'),
        output.dependencies,
      )),
      targetArchitecture: targetArchitecture,
      targetOS: targetOS,
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {'ffi_path': library.path},
          basePath: Directory.current.uri,
        ),
      ),
    );

    return built.singleOrNull ?? fail('the hook ran once');
  }

  // The id the bindings load, read from their source, not a copy of it.
  final defaultAsset =
      RegExp(r"@DefaultAsset\('([^']+)'\)")
          .firstMatch(
            File('lib/src/core/native/gleon_ffi.dart').readAsStringSync(),
          )
          ?.group(1) ??
      fail('gleon_ffi.dart has no @DefaultAsset');

  for (final NativeTarget(:arch, :key, :libFileName, :os)
      in NativeTarget.values) {
    test(
      '$key bundles the library under the asset id of the bindings',
      () async {
        final dir = Directory.systemTemp.createTempSync('gleon_hook_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final library = File.fromUri(dir.uri.resolve(libFileName))
          ..writeAsBytesSync([0]);

        final (asset, dependencies) = await build(
          library,
          targetOS: .fromString(os),
          targetArchitecture: .fromString(arch),
        );

        expect(asset.id, defaultAsset);
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        expect(asset.file, library.uri);
        expect(dependencies, [library.uri]);
      },
    );
  }

  // The real library of this host (CI builds one on each), so code_assets
  // also checks its file format and architecture.
  final local = switch (NativeTarget.host) {
    NativeTarget(:final key, :final libFileName) => File(
      'native/$key/$libFileName',
    ).absolute,
    null => null,
  };
  test(
    'the local build of this host passes the architecture check',
    () async {
      final library = local ?? fail('no host target');
      final (built, _) = await build(
        library,
        targetOS: .current,
        targetArchitecture: .current,
      );

      expect(built.file, library.uri);
    },
    skip: local != null && local.existsSync()
        ? false
        : 'needs a local build of this host (dart bin/build_native.dart)',
  );
}
