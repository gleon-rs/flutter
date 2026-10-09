/// Build hook that provides the `gleon-ffi` native library to Dart: from the
/// `ffi_path` or `gleon_repo` user-defines, `native/<target>/` of this
/// package, or the GitHub Release of its version (see `NativeLibrary` in
/// `lib/src/core/hook/native_library.dart`).
///
/// Flutter runs the hooks of dev_dependencies for every non-release build of
/// an app, so targets without a library (Android, iOS, other architectures)
/// get no asset and no error: a golden compared there fails with the
/// missing-library message of `NativeEngine.loadAbiVersion`. Web builds ask
/// for no code assets at all.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:gleon/src/core/hook/hook_user_defines.dart';
import 'package:gleon/src/core/hook/native_library.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:hooks/hooks.dart';

/// Must match the `@DefaultAsset` of `lib/src/core/native/gleon_ffi.dart`.
const _assetName = 'src/core/native/gleon_ffi.dart';

Future<void> main(List<String> args) => build(args, _build);

Future<void> _build(BuildInput input, BuildOutputBuilder output) async {
  final BuildInput(
    :config,
    :outputDirectoryShared,
    :packageName,
    :packageRoot,
    :userDefines,
  ) = input;
  if (!config.buildCodeAssets) return;
  final CodeConfig(:targetArchitecture, :targetOS) = config.code;
  final requested = NativeTarget.byKey(
    '${targetOS.name}-${targetArchitecture.name}',
  );
  if (requested == null) return;
  final (:dependencies, :library) = await NativeLibrary(
    packageRoot: packageRoot,
    userDefines: HookUserDefines(userDefines),
    sharedOutputDir: outputDirectoryShared,
    target: requested,
    environment: Platform.environment,
  ).resolve();
  output.dependencies.addAll(dependencies);
  output.assets.code.add(
    CodeAsset(
      package: packageName,
      name: _assetName,
      linkMode: DynamicLoadingBundled(),
      file: library,
    ),
  );
}
