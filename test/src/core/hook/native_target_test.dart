import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';

void main() {
  test('windows builds link the C runtime statically in every setup', () {
    const flag = '-C target-feature=+crt-static';
    const windows = NativeTarget.windowsX64;
    expect(windows.cargoEnvironment(const {}), {
      'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS': flag,
    });
    // Cargo ignores per-target flags when RUSTFLAGS is set: append instead.
    expect(windows.cargoEnvironment(const {'RUSTFLAGS': '-D warnings'}), {
      'RUSTFLAGS': '-D warnings $flag',
    });
    expect(
      windows.cargoEnvironment(const {'CARGO_ENCODED_RUSTFLAGS': '-Dwarnings'}),
      {
        'CARGO_ENCODED_RUSTFLAGS':
            '-Dwarnings\x1f-C\x1ftarget-feature=+crt-static',
      },
    );
    expect(
      NativeTarget.linuxX64.cargoEnvironment(const {'RUSTFLAGS': 'x'}),
      isEmpty,
    );
  });

  test('target keys match code_assets and dart:ffi naming', () {
    expect(NativeTarget.byKey('macos-arm64'), NativeTarget.macosArm64);
    expect(NativeTarget.byKey('windows-x64'), NativeTarget.windowsX64);
    expect(NativeTarget.byKey('macos-x64'), isNull);
    expect(
      NativeTarget.keys,
      'linux-arm64, linux-x64, macos-arm64, windows-x64',
    );
  });

  test('only a build of the pinned commit serves the pin', () {
    const pin = '47125b6cc63fe9dfe07cb3e736eb8a902da38cac';
    expect(NativeTarget.isBuildOfPin(pin, pin), isTrue);
    expect(NativeTarget.isBuildOfPin('$pin-dirty', pin), isTrue);
    for (final other in [null, '(unknown)', 'e957394', '$pin-other']) {
      expect(NativeTarget.isBuildOfPin(other, pin), isFalse, reason: other);
    }
  });

  test('release asset names are unique per target', () {
    final names = NativeTarget.values.map((target) => target.assetName);
    expect(names.toSet(), hasLength(NativeTarget.values.length));
    expect(NativeTarget.windowsX64.assetName, 'gleon_ffi-windows-x64.dll');
    expect(NativeTarget.macosArm64.assetName, 'libgleon_ffi-macos-arm64.dylib');
  });
}
