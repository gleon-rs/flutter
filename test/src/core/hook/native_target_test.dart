import 'dart:ffi' show Abi;

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';

void main() {
  test('the built library lies in the target directory, slash or not', () {
    const linux = NativeTarget.linuxX64;
    final expected = Uri.file(
      '/w/target/x86_64-unknown-linux-gnu/release/libgleon_ffi.so',
    );
    expect(linux.builtLibrary(.file('/w/target/')), expected);
    expect(linux.builtLibrary(.file('/w/target')), expected);
  });

  test('gleon names every target like Rust std::env::consts', () {
    expect(
      {for (final target in NativeTarget.values) target.gleonPlatform},
      {'linux-aarch64', 'linux-x86_64', 'macos-aarch64', 'windows-x86_64'},
    );
  });

  test('the host is the target of its ABI, none for an unsupported one', () {
    const targets = {
      Abi.linuxArm64: NativeTarget.linuxArm64,
      Abi.linuxX64: NativeTarget.linuxX64,
      Abi.macosArm64: NativeTarget.macosArm64,
      Abi.windowsX64: NativeTarget.windowsX64,
    };
    expect(NativeTarget.host, targets[Abi.current()]);
  });

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

  test('windows builds keep the target and build rustflags', () {
    const targetFlags = 'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS';
    const windows = NativeTarget.windowsX64;
    expect(windows.cargoEnvironment(const {targetFlags: '-D warnings'}), {
      targetFlags: '-D warnings -C target-feature=+crt-static',
    });
    // The target's flags beat `build.rustflags`, so they carry those too.
    expect(
      windows.cargoEnvironment(const {
        'CARGO_BUILD_RUSTFLAGS': '-C debuginfo=1',
      }),
      {targetFlags: '-C debuginfo=1 -C target-feature=+crt-static'},
    );
    // Like cargo: with both, the build's flags are not used.
    expect(
      windows.cargoEnvironment(const {
        'CARGO_BUILD_RUSTFLAGS': '-C debuginfo=1',
        targetFlags: '-D warnings',
      }),
      {targetFlags: '-D warnings -C target-feature=+crt-static'},
    );
  });

  test('the hook asks for a library of supported targets only', () {
    expect(NativeTarget.byKey('linux-arm64'), NativeTarget.linuxArm64);
    expect(NativeTarget.byKey('macos-arm64'), NativeTarget.macosArm64);
    // Flutter runs the hooks of dev_dependencies for app builds too: those
    // get no library instead of a failing build.
    for (final (os, arch) in [
      ('android', 'arm64'),
      ('ios', 'arm64'),
      ('linux', 'riscv64'),
      ('macos', 'x64'),
    ]) {
      expect(NativeTarget.byKey('$os-$arch'), isNull, reason: '$os-$arch');
    }
  });

  group('build_native targets', () {
    List<String> keys(
      List<String> requested, {
      required String hostOs,
      required NativeTarget? host,
    }) => [
      for (final target in NativeTarget.resolveKeys(
        requested,
        hostOs: hostOs,
        host: host,
      ))
        target.key,
    ];

    Map<String, List<String>?> subcommands(String hostOs, NativeTarget host) =>
        {
          for (final target in NativeTarget.values)
            target.key: target.cargoSubcommand(hostOs: hostOs, host: host),
        };

    test('macOS builds everything, Linux and Windows through wrappers', () {
      expect(subcommands('macos', .macosArm64), {
        'linux-arm64': ['zigbuild'],
        'linux-x64': ['zigbuild'],
        'macos-arm64': ['build'],
        'windows-x64': ['xwin', 'build'],
      });
      expect(keys(['all'], hostOs: 'macos', host: .macosArm64), [
        'linux-arm64',
        'linux-x64',
        'macos-arm64',
        'windows-x64',
      ]);
    });

    test('Linux builds the other architecture with zigbuild', () {
      expect(subcommands('linux', .linuxX64), {
        'linux-arm64': ['zigbuild'],
        'linux-x64': ['build'],
        'macos-arm64': null,
        'windows-x64': ['xwin', 'build'],
      });
      expect(subcommands('linux', .linuxArm64)['linux-arm64'], ['build']);
      expect(keys(['all'], hostOs: 'linux', host: .linuxArm64), [
        'linux-arm64',
        'linux-x64',
        'windows-x64',
      ]);
    });

    test('Windows builds itself with cargo and Linux with zigbuild', () {
      expect(subcommands('windows', .windowsX64), {
        'linux-arm64': ['zigbuild'],
        'linux-x64': ['zigbuild'],
        'macos-arm64': null,
        'windows-x64': ['build'],
      });
    });

    test('keys keep their order once each', () {
      expect(
        keys(['host', 'linux-arm64', 'all'], hostOs: 'linux', host: .linuxX64),
        ['linux-x64', 'linux-arm64', 'windows-x64'],
      );
    });

    test('every target is checked before anything is built', () {
      Matcher throwsFormat(String message) => throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(message),
        ),
      );
      expect(
        () => keys(
          ['linux-x64', 'macos-arm64'],
          hostOs: 'linux',
          host: .linuxX64,
        ),
        throwsFormat('macos-arm64 can only be built on macos'),
      );
      expect(
        () => keys(['host'], hostOs: 'macos', host: null),
        throwsFormat('this host is not a supported target'),
      );
      expect(
        () => keys(['macos-x64'], hostOs: 'macos', host: .macosArm64),
        throwsFormat('unknown target macos-x64'),
      );
    });
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
