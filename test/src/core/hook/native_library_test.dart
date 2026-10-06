import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_library.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';
import 'package:gleon/src/core/hook/user_defines.dart';

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

  Future<({List<Uri> dependencies, Uri library})> resolve(
    Uri packageRoot, {
    Map<String, Object> userDefines = const {},
    Map<String, String> environment = const {},
    _FakeCargo? cargo,
  }) => NativeLibrary(
    packageRoot: packageRoot,
    userDefines: _MapUserDefines(userDefines),
    sharedOutputDir: dir('shared'),
    target: target,
    environment: environment,
  ).resolve(runProcess: (cargo ?? .never).run);

  Matcher throwsState(Matcher message) => throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );

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

  test('gleon_repo builds the checkout, before a bundled library', () async {
    write('gleon/Cargo.toml', '[workspace]');
    write('gleon/gleon-ffi/Cargo.toml', '[package]');
    write('gleon/gleon-ffi/src/lib.rs', '// Rust');
    write('bin/${Platform.isWindows ? 'cargo.exe' : 'cargo'}');
    bundle();
    final cargo = _FakeCargo();

    final (:dependencies, :library) = await resolve(
      package(),
      userDefines: {'gleon_repo': '${tempPath()}/gleon'},
      environment: {'PATH': '${tempPath()}/bin'},
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
  });

  group('a bundled library', () {
    test('is used as is without a pin (the pub.dev archive)', () async {
      final bundled = bundle();

      final (:dependencies, :library) = await resolve(package());
      expect(library, bundled);
      expect(dependencies, [dir('package/native'), bundled]);
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
          dir('package/native'),
          packageRoot.resolve('pubspec.yaml'),
          fetched,
        ]);
      });
    }

    test('names release_url when the mirror lacks the release', () async {
      final server = await ReleaseServer.start(const {});
      addTearDown(server.close);

      await expectLater(
        resolve(package(), userDefines: {'release_url': '${server.url}'}),
        throwsState(allOf(contains('HTTP 404'), contains('`release_url`'))),
      );
    });

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

/// Builds nothing but the library file cargo would write.
final class _FakeCargo {
  _FakeCargo({this.isAllowed = true});

  /// A runner that fails the test when called.
  static final never = _FakeCargo(isAllowed: false);

  /// Whether cargo may run at all.
  final bool isAllowed;

  /// Arguments of every call.
  final calls = <List<String>>[];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) {
    if (!isAllowed) fail('cargo must not run: $arguments');
    calls.add(arguments);
    String after(String flag) =>
        arguments
            .skipWhile((argument) => argument != flag)
            .skip(1)
            .firstOrNull ??
        fail('cargo was called without $flag');
    File(
      '${after('--target-dir')}/${after('--target')}/release/libgleon_ffi.so',
    ).createSync(recursive: true);

    return .value(ProcessResult(1, 0, 'out', 'err'));
  }
}
