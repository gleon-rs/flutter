import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../hook/build.dart' as hook;

void main() {
  // Flutter runs the build hooks of dev_dependencies for every debug build
  // of an app, so a target without a library must not fail that build.
  for (final (os, arch) in [
    (OS.android, Architecture.arm64),
    (OS.iOS, Architecture.arm64),
    (OS.linux, Architecture.riscv64),
  ]) {
    test('$os-$arch gets no library and no error', () async {
      final built = <({int assets, int dependencies})>[];
      await testCodeBuildHook(
        mainMethod: hook.main,
        check: (_, output) => built.add((
          assets: output.assets.encodedAssets.length,
          dependencies: output.dependencies.length,
        )),
        targetArchitecture: arch,
        targetOS: os,
      );
      expect(built, [(assets: 0, dependencies: 0)]);
    });
  }
}
