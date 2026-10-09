import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
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

  for (final (os, arch, fileName) in [
    (OS.linux, Architecture.arm64, 'libgleon_ffi.so'),
    (OS.linux, Architecture.x64, 'libgleon_ffi.so'),
    (OS.macOS, Architecture.arm64, 'libgleon_ffi.dylib'),
    (OS.windows, Architecture.x64, 'gleon_ffi.dll'),
  ]) {
    test(
      '$os-$arch bundles the library under the asset id of the bindings',
      () async {
        final dir = Directory.systemTemp.createTempSync('gleon_hook_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final library = File('${dir.path}/$fileName')..writeAsBytesSync([0]);

        final (asset, dependencies) = await build(
          library,
          targetOS: os,
          targetArchitecture: arch,
        );

        expect(asset.id, 'package:gleon/src/core/native/gleon_ffi.dart');
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        expect(asset.file, library.uri);
        expect(dependencies, [library.uri]);
      },
    );
  }

  // A real library, so code_assets also checks its architecture.
  final local = File('native/macos-arm64/libgleon_ffi.dylib');
  test(
    'the local macOS build passes the architecture check',
    () async {
      final (asset, _) = await build(
        local.absolute,
        targetOS: .macOS,
        targetArchitecture: .arm64,
      );

      expect(asset.file, local.absolute.uri);
    },
    skip: Platform.isMacOS && local.existsSync()
        ? false
        : 'needs a local macOS build (dart bin/build_native.dart)',
  );
}
