/// Build hook that provides the `gleon-ffi` native library to Dart: from the
/// `ffi_path` or `gleon_repo` user-defines, `native/<target>/` of this
/// package, or the GitHub Release of its version (see `NativeLibrary` in
/// `lib/src/core/hook/native_library.dart`).
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
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
  final (:dependencies, :library) = await NativeLibrary(
    packageRoot: packageRoot,
    userDefines: .of(userDefines),
    sharedOutputDir: outputDirectoryShared,
    target: NativeTarget.requested(targetOS.name, targetArchitecture.name),
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
