// The tree of `pub publish --dry-run` is drawn with box characters.
// ignore_for_file: avoid-non-ascii-symbols

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import '../../bin/src/check_failure.dart';
import '../../bin/src/publish_bundle.dart';
import '../../bin/src/release_server.dart';

void main() {
  const pin = '0123456789abcdef0123456789abcdef01234567';

  /// A temporary directory, deleted with the test.
  Directory temp(String name) {
    final dir = Directory.systemTemp.createTempSync('gleon_publish_$name');
    addTearDown(() => dir.deleteSync(recursive: true));

    return dir;
  }

  /// A release of a library per target (its bytes name the target) that
  /// names [releasedPin] as the gleon commit of its libraries.
  Future<ReleaseServer> release({String releasedPin = pin}) async {
    final dir = temp('release');
    final server = await ReleaseServer.start({
      for (final target in NativeTarget.values)
        target.assetName: File('${dir.path}/${target.assetName}')
          ..writeAsStringSync('library of ${target.key}'),
      ReleaseDownload.pinFileName: File('${dir.path}/pin')
        ..writeAsStringSync('$releasedPin\n'),
    });
    addTearDown(server.close);

    return server;
  }

  /// A copy of the package that pins [pin].
  Directory package() {
    final dir = temp('package');
    File.fromUri(NativeTarget.pinFile(dir.uri))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('$pin\n');

    return dir;
  }

  group('bundleLibraries', () {
    test('puts the verified library of every target into native/', () async {
      final server = await release();
      final copy = package();

      await bundleLibraries(
        package: copy,
        releaseUrl: server.url,
        version: '1.0.0',
        cacheDir: temp('cache'),
      );

      for (final target in NativeTarget.values) {
        expect(
          File.fromUri(target.bundledLibrary(copy.uri)).readAsStringSync(),
          'library of ${target.key}',
        );
      }
      // Each file of the release once: the checksum list and the pin are
      // cached by the first target, not fetched by every one.
      expect(server.requests, hasLength(NativeTarget.values.length + 2));
      expect(server.requests.toSet(), {
        ReleaseDownload.checksumsFileName,
        ReleaseDownload.pinFileName,
        for (final target in NativeTarget.values) target.assetName,
      });
    });

    test('refuses a release built from another gleon commit', () async {
      final server = await release(releasedPin: 'f' * 40);
      final copy = package();

      await expectLater(
        bundleLibraries(
          package: copy,
          releaseUrl: server.url,
          version: '1.0.0',
          cacheDir: temp('cache'),
        ),
        throwsA(
          isA<CheckFailure>().having(
            (failure) => failure.message,
            'message',
            allOf(contains(pin), contains('f' * 40)),
          ),
        ),
      );
    });

    test('refuses a release that names no gleon commit', () async {
      final dir = temp('unpinned_release');
      final server = await ReleaseServer.start({
        for (final target in NativeTarget.values)
          target.assetName: File('${dir.path}/${target.assetName}')
            ..writeAsStringSync('library of ${target.key}'),
      });
      addTearDown(server.close);

      await expectLater(
        bundleLibraries(
          package: package(),
          releaseUrl: server.url,
          version: '1.0.0',
          cacheDir: temp('cache'),
        ),
        throwsA(
          isA<CheckFailure>().having(
            (failure) => failure.message,
            'message',
            contains('names no gleon commit'),
          ),
        ),
      );
    });

    test('needs the pin of the package', () async {
      final server = await release();

      await expectLater(
        bundleLibraries(
          package: temp('unpinned'),
          releaseUrl: server.url,
          version: '1.0.0',
          cacheDir: temp('cache'),
        ),
        throwsA(isA<CheckFailure>()),
      );
    });
  });

  group('archiveFiles', () {
    test('reads the paths of the files of the tree', () {
      const output = '''
Resolving dependencies...
Publishing gleon 1.0.0 to https://pub.dev:
├── CHANGELOG.md (18 KB)
├── example
│   ├── .gleon
│   │   └── gleon.yaml (<1 KB)
│   └── README.md (<1 KB)
├── lib
│   └── gleon.dart (1 KB)
├── native
│   ├── linux-arm64
│   │   └── libgleon_ffi.so (1 MB)
│   └── macos-arm64
│       └── libgleon_ffi.dylib (1007 KB)
└── pubspec.yaml (1 KB)

Total compressed archive size: 881 KB.
''';

      expect(archiveFiles(output), [
        'CHANGELOG.md',
        'example/.gleon/gleon.yaml',
        'example/README.md',
        'lib/gleon.dart',
        'native/linux-arm64/libgleon_ffi.so',
        'native/macos-arm64/libgleon_ffi.dylib',
        'pubspec.yaml',
      ]);
    });

    // A file is told from a directory by what follows it, not by its size: a
    // size pub prints in another way stays part of the name (and then fails
    // the check of the archive) instead of hiding the file.
    test('reads a file without a size as a file', () {
      const output = '''
├── lib
│   └── gleon.dart
├── NOTICE (12 bytes)
└── pubspec.yaml (1 KB)
''';

      expect(archiveFiles(output), [
        'lib/gleon.dart',
        'NOTICE (12 bytes)',
        'pubspec.yaml',
      ]);
    });

    // The tree of a real `flutter pub publish --dry-run` of this package
    // (Flutter 3.50, with a local build of one library).
    test('reads the tree of a real dry run', () {
      final files = archiveFiles(
        File('test/tooling/fixtures/pub_publish_dry_run.txt')
            .readAsStringSync(),
      );

      expect(files, containsAll(alwaysShipped));
      expect(
        files,
        containsAll([
          'example/.gleon/gleon.yaml',
          'example/linux/runner/main.cc',
          'lib/src/flutter/text_regions.dart',
          'native/macos-arm64/libgleon_ffi.dylib',
        ]),
      );
      expect(files.where((file) => file.contains(' (')), isEmpty);
      expect(archiveProblems(files), [
        for (final target in NativeTarget.values)
          if (target != .macosArm64)
            'the archive lacks native/${target.key}/${target.libFileName}',
      ]);
    });
  });

  group('archiveProblems', () {
    final libraries = [
      for (final target in NativeTarget.values)
        'native/${target.key}/${target.libFileName}',
    ];

    test('none for the libraries of every target and the package', () {
      expect(archiveProblems([...libraries, ...alwaysShipped]), isEmpty);
    });

    // A list read wrong (pub changed its tree) lacks the files every archive
    // has: it never passes as an archive without maintainer files.
    test('an empty list is no archive', () {
      expect(
        archiveProblems(const []),
        containsAll([for (final file in alwaysShipped) _lacks(file)]),
      );
    });

    test('names a missing library and what consumers must not get', () {
      final [missing, ...present] = libraries;

      expect(
        archiveProblems([
          ...present,
          'native/gleon_ref',
          'native/macos-arm64/gleon_ref',
          'bin/build_native.dart',
          'test/helpers/png.dart',
          'coverage/lcov.info',
          'CLAUDE.local.md',
          'example/benchmark/alchemist_expectation_test.dart',
          'example/test/failures/counter_page_gleonDiff.png',
          'example/.gleon/runs/latest/cases/a.json',
          'example/build/unit_test_assets/AssetManifest.bin',
          'example/test/counter_test.dart',
          ...alwaysShipped,
          // A name that only starts like a maintainer path ships.
          'binaries.md',
        ]),
        [
          'the archive lacks $missing',
          for (final file in [
            'native/gleon_ref',
            'native/macos-arm64/gleon_ref',
            'bin/build_native.dart',
            'test/helpers/png.dart',
            'coverage/lcov.info',
            'CLAUDE.local.md',
            'example/benchmark/alchemist_expectation_test.dart',
            'example/test/failures/counter_page_gleonDiff.png',
            'example/.gleon/runs/latest/cases/a.json',
            'example/build/unit_test_assets/AssetManifest.bin',
          ])
            'the archive holds $file, which consumers must not get',
        ],
      );
    });

    // `.pubignore` is the list pub applies; this one is checked after it, so
    // a line dropped from `.pubignore` is caught.
    test('knows every top-level path .pubignore leaves out', () {
      final topLevel = RegExp(r'^/([^/*!#\s][^*\s]*?)/?$');
      final ignored = [
        for (final line in File('.pubignore').readAsLinesSync())
          ?topLevel.firstMatch(line.trim())?.group(1),
      ];

      expect(
        maintainerOnly,
        containsAll(ignored.where((path) => !path.startsWith('native'))),
      );
    });
  });
}

/// The problem of an archive without [file], a file every archive holds.
String _lacks(String file) =>
    'the archive lacks $file (or the file list of pub was not read right)';
