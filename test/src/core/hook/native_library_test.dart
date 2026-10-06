import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_library.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';
import 'package:gleon/src/core/hook/user_defines.dart';

import '../../../helpers/fake_cargo.dart';
import '../../../helpers/release_server.dart';

void main() {
  // Host-independent: no library is loaded, so any target will do.
  const target = NativeTarget.linuxX64;
  final NativeTarget(:assetName, :key, :libFileName, :rustTriple) = target;
  const pin = '47125b6cc63fe9dfe07cb3e736eb8a902da38cac';

  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_library_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  String tempPath() => (temp ?? .systemTemp).path;

  Uri dir(String path) => Directory('${tempPath()}/$path').uri;

  /// A package root whose `pubspec.yaml` has a version unless not
  /// [hasVersion].
  Uri package({bool hasVersion = true}) {
    File('${tempPath()}/package/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        ['name: gleon', if (hasVersion) 'version: 1.0.0'].join('\n'),
      );

    return dir('package');
  }

  /// Writes [content] to [path] below the temp directory.
  File write(String path, [String content = 'x']) {
    final file = File('${tempPath()}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);

    return file;
  }

  /// A bundled library of [target], with a [stamp] and a pin [pinned] when
  /// given.
  Uri bundle({String? stamp, String? pinned}) {
    const native = 'package/native';
    final library = write('$native/$key/$libFileName');
    if (stamp != null) write('$native/$key/gleon_ref', '$stamp\n');
    if (pinned != null) write('$native/gleon_ref', '$pinned\n');

    return library.uri;
  }

  /// What a bundled library depends on, present or not: `native/`, the
  /// library, the pin and the library's stamp.
  List<Uri> bundleInputs() => [
    dir('package/native'),
    dir('package/native').resolve('$key/$libFileName'),
    dir('package/native').resolve('gleon_ref'),
    dir('package/native').resolve('$key/gleon_ref'),
  ];

  Future<({List<Uri> dependencies, Uri library})> resolve(
    Uri packageRoot, {
    Map<String, Object> userDefines = const {},
    Map<String, String> environment = const {},
    FakeCargo? cargo,
    NativeTarget requested = target,
  }) => NativeLibrary(
    packageRoot: packageRoot,
    userDefines: _MapUserDefines(userDefines),
    sharedOutputDir: dir('shared'),
    target: requested,
    environment: environment,
  ).resolve(runProcess: (cargo ?? FakeCargo.never()).run);

  Matcher throwsState(Object message) => throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );

  for (final define in ['ffi_path', 'gleon_repo']) {
    for (final value in <Object>[
      42,
      ['a.so'],
    ]) {
      test('$define must be a path, not $value', () async {
        bundle();

        await expectLater(
          resolve(package(), userDefines: {define: value}),
          throwsState(
            'gleon: user-define `$define` must be a path, got $value',
          ),
        );
      });
    }
  }

  group('ffi_path', () {
    test('wins over a checkout and a bundled library', () async {
      final override = write('lib/libgleon_ffi.so').uri;
      bundle();

      final (:dependencies, :library) = await resolve(
        package(),
        userDefines: {
          'ffi_path': override.toFilePath(),
          'gleon_repo': '${tempPath()}/gleon',
        },
      );
      expect(library, override);
      expect(dependencies, [override]);
    });

    test('names the user-define when the file is missing', () async {
      await expectLater(
        resolve(
          package(),
          userDefines: {'ffi_path': '${tempPath()}/missing.so'},
        ),
        throwsState(allOf(contains('`ffi_path`'), contains('missing.so'))),
      );
    });
  });

  group('gleon_repo', () {
    /// A gleon checkout and a cargo on `PATH`; the environment to find it.
    Map<String, String> checkout() {
      write('gleon/Cargo.toml', '[workspace]');
      write('gleon/gleon-ffi/Cargo.toml', '[package]');
      write('gleon/gleon-ffi/src/lib.rs', '// Rust');
      write('bin/${Platform.isWindows ? 'cargo.exe' : 'cargo'}');

      return {'PATH': '${tempPath()}/bin'};
    }

    test(
      'builds the checkout, before a bundled library and a mirror',
      () async {
        final environment = checkout();
        bundle();
        final cargo = FakeCargo();

        final (:dependencies, :library) = await resolve(
          package(),
          userDefines: {
            'gleon_repo': '${tempPath()}/gleon',
            // Never asked: the download fails the test (no server).
            'release_url': 'http://127.0.0.1:9/v1.0.0/',
          },
          environment: environment,
          cargo: cargo,
        );
        expect(
          library,
          dir('shared').resolve('cargo/$rustTriple/release/$libFileName'),
        );
        expect(cargo.calls, hasLength(1));
        expect(
          dependencies.map((uri) => uri.pathSegments.lastOrNull),
          containsAll(['Cargo.toml', 'lib.rs']),
        );
      },
    );

    test('passes the environment on to cargo', () async {
      const windows = NativeTarget.windowsX64;
      final cargo = FakeCargo();

      await resolve(
        package(),
        userDefines: {'gleon_repo': '${tempPath()}/gleon'},
        environment: {...checkout(), 'CARGO_BUILD_RUSTFLAGS': '-C debuginfo=1'},
        cargo: cargo,
        requested: windows,
      );
      expect(cargo.environments, [
        windows.cargoEnvironment(const {
          'CARGO_BUILD_RUSTFLAGS': '-C debuginfo=1',
        }),
      ]);
      expect(
        cargo.environments.singleOrNull,
        containsPair(
          'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS',
          '-C debuginfo=1 -C target-feature=+crt-static',
        ),
      );
    });
  });

  group('a bundled library', () {
    test('is used as is without a pin (the pub.dev archive)', () async {
      final bundled = bundle();

      final (:dependencies, :library) = await resolve(package());
      expect(library, bundled);
      expect(dependencies, bundleInputs());
    });

    for (final stamp in [pin, '$pin${NativeTarget.dirtySuffix}']) {
      test('is used when built from the pin ($stamp)', () async {
        final bundled = bundle(stamp: stamp, pinned: pin);

        final (:dependencies, :library) = await resolve(package());
        expect(library, bundled);
        expect(
          dependencies,
          containsAll([
            dir('package/native').resolve('gleon_ref'),
            dir('package/native').resolve('$key/gleon_ref'),
          ]),
        );
      });
    }

    test('wins over release_url', () async {
      final bundled = bundle();

      final (dependencies: _, :library) = await resolve(
        package(),
        // Never asked: the download fails the test (no server).
        userDefines: {'release_url': 'http://127.0.0.1:9/v1.0.0/'},
      );
      expect(library, bundled);
    });

    test('of another commit is refused with what to do', () async {
      bundle(stamp: 'e957394', pinned: pin);

      await expectLater(
        resolve(package()),
        throwsState(
          allOf(
            contains('built from gleon e957394'),
            contains(pin),
            contains('bin/build_native.dart'),
            contains('gleon_repo'),
          ),
        ),
      );
    });

    test('without a stamp is refused while a pin exists', () async {
      bundle(pinned: pin);

      await expectLater(
        resolve(package()),
        throwsState(contains('built from gleon (unknown)')),
      );
    });
  });

  group('the release download', () {
    final library = List<int>.generate(512, (i) => i % 7);
    final sums = '${sha256.convert(library)}  $assetName\n'.codeUnits;

    Future<ReleaseServer> mirror() async {
      final server = await ReleaseServer.start({
        ReleaseDownload.checksumsFileName: sums,
        assetName: library,
      });
      addTearDown(server.close);

      return server;
    }

    for (final hasSlash in [true, false]) {
      test('takes release_url (trailing slash: $hasSlash)', () async {
        final server = await mirror();
        final url = server.url;
        final version = url.pathSegments.firstOrNull ?? fail('no version');
        final packageRoot = package();

        final (:dependencies, library: fetched) = await resolve(
          packageRoot,
          userDefines: {
            'release_url': hasSlash
                ? '$url'
                : '${url.resolve('..').resolve(version)}',
          },
        );
        expect(File.fromUri(fetched).readAsBytesSync(), library);
        expect(dependencies, [
          ...bundleInputs(),
          packageRoot.resolve('pubspec.yaml'),
          fetched,
        ]);
      });
    }

    test('happens with a pin but no bundled library', () async {
      final server = await mirror();
      write('package/native/gleon_ref', '$pin\n');

      final (:dependencies, library: fetched) = await resolve(
        package(),
        userDefines: {'release_url': '${server.url}'},
      );
      expect(File.fromUri(fetched).readAsBytesSync(), library);
      // The hooks runner hashes directories non-recursively and re-runs the
      // hook when a missing file appears: a later local build is seen.
      expect(dependencies, containsAll(bundleInputs()));
    });

    test('names release_url when the mirror lacks the release', () async {
      final server = await ReleaseServer.start(const {});
      addTearDown(server.close);

      await expectLater(
        resolve(package(), userDefines: {'release_url': '${server.url}'}),
        throwsState(allOf(contains('HTTP 404'), contains('`release_url`'))),
      );
    });

    for (final url in [
      'https://mirror.example/v1.0.0?channel=stable',
      'https://mirror.example/v1.0.0/#assets',
    ]) {
      test('refuses a release_url with a query or fragment: $url', () async {
        await expectLater(
          resolve(package(), userDefines: {'release_url': url}),
          throwsState(
            allOf(
              contains('`release_url`'),
              contains('query or fragment'),
              contains(url),
            ),
          ),
        );
      });
    }

    test('refuses a release_url that is no string', () async {
      await expectLater(
        resolve(package(), userDefines: {'release_url': 42}),
        throwsState(contains('must be a string')),
      );
    });

    test('needs the package version', () async {
      await expectLater(
        resolve(package(hasVersion: false)),
        throwsState(contains('no `version`')),
      );
    });
  });
}

/// User-defines from a map; paths are file paths.
final class _MapUserDefines implements UserDefines {
  const _MapUserDefines(this._defines);

  final Map<String, Object> _defines;

  @override
  Object? operator [](String key) => _defines[key];

  @override
  Uri? path(String key) => switch (_defines[key]) {
    final String path => .file(path),
    _ => null,
  };
}
