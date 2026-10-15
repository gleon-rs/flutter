import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/src/check_failure.dart';
import '../../bin/src/consumer_app.dart';
import '../../bin/src/consumer_check.dart';
import '../../bin/src/release_server.dart';
import '../../bin/src/run_resources.dart';
import '../../bin/src/stray_home_config.dart';

void main() {
  Directory temp(String prefix) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() => dir.deleteSync(recursive: true));

    return dir;
  }

  // The copy is what a consumer gets: whatever `.pubignore` leaves out at the
  // top level of the archive is not copied either (a file the package needs
  // but pub drops would pass here and fail on pub.dev otherwise).
  test('copies nothing the archive leaves out', () {
    final topLevel = RegExp(r'^/?([^/*!#\s][^/*\s]*)/?$');
    final ignored = [
      for (final line in File('.pubignore').readAsLinesSync())
        ?topLevel.firstMatch(line.trim())?.group(1),
    ];

    expect(ignored, containsAll(['bin', 'benchmark', 'pubspec.lock']));
    expect(notShipped, containsAll(ignored));
  });

  // By what a directory holds, not by its name: Homebrew puts cargo into
  // /opt/homebrew/bin. A directory that holds Flutter too stays (the check
  // then relies on no source build having run).
  test('PATH loses the directories that hold Rust', () {
    const tools = {
      '/home/me/.cargo/bin': {'cargo', 'rustup'},
      '/home/me/flutter/bin': {'flutter', 'dart'},
      '/opt/homebrew/bin': {'cargo', 'rustc', 'git'},
      '/usr/bin': {'git'},
      '/usr/local/bin': {'cargo', 'flutter'},
    };

    expect(
      pathWithoutRust(
        tools.keys.join(':'),
        separator: ':',
        holds: (dir, tool) => tools[dir]?.contains(tool) ?? false,
      ),
      '/home/me/flutter/bin:/usr/bin:/usr/local/bin',
    );
  });

  // The work directory must lie outside the package it copies: by its
  // resolved path (`..`, symbolic links), not by the spelling of either.
  test('a work directory inside the package is found however named', () {
    final root = temp('gleon_consumer_root_');
    final package = Directory('${root.path}/flutter')..createSync();
    final inside = Directory('${package.path}/tmp')..createSync();
    final sibling = Directory('${root.path}/flutter2')..createSync();

    expect(isWithin(Directory('${root.path}/flutter'), package), isTrue);
    expect(isWithin(inside, package), isTrue);
    expect(isWithin(Directory('${inside.path}/..'), package), isTrue);
    expect(isWithin(sibling, package), isFalse);
    expect(
      isWithin(Directory('${package.path}/../flutter2'), package),
      isFalse,
    );
    expect(isWithin(root, package), isFalse);
    // Creating symbolic links needs a privilege on Windows.
    if (!Platform.isWindows) {
      final link = Link('${root.path}/work')..createSync(inside.path);
      expect(isWithin(Directory(link.path), package), isTrue);
    }
  });

  // Shared by the end of a run and an interrupt (Ctrl+C skips `finally`).
  test('a run cleans up once, the work directory unless kept', () async {
    final home = temp('gleon_consumer_home_');
    // Not `temp`: the cleanup deletes it.
    final work = Directory.systemTemp.createTempSync('gleon_consumer_work_');
    addTearDown(() => _deleteIfLeft(work));
    final resources = RunResources(work, isKept: false)
      ..stray = StrayHomeConfig.write(home.path);
    final config = resources.stray?.file;

    await resources.cleanUp();
    await resources.cleanUp();
    expect(config?.existsSync(), isFalse);
    expect(work.existsSync(), isFalse);

    final kept = temp('gleon_consumer_kept_');
    await RunResources(kept, isKept: true).cleanUp();
    expect(kept.existsSync(), isTrue);
  });

  // An interrupt during the cleanup at the end of a run (or the other way
  // round) waits for it: the process exits only once everything is gone.
  test('a second cleanup waits for the first', () async {
    final work = Directory.systemTemp.createTempSync('gleon_consumer_work_');
    addTearDown(() => _deleteIfLeft(work));
    final resources = RunResources(work, isKept: false)
      ..server = await ReleaseServer.start({});

    final first = resources.cleanUp();
    await resources.cleanUp();
    expect(work.existsSync(), isFalse);
    await first;
  });

  test('copies the package without what consumers never get', () {
    final from = temp('gleon_consumer_from_');
    for (final file in [
      'pubspec.yaml',
      'lib/gleon.dart',
      'lib/src/core/native/gleon_ffi.dart',
      'hook/build.dart',
      'native/macos-arm64/libgleon_ffi.dylib',
      'native/gleon_ref',
      'test/a_test.dart',
      'example/pubspec.yaml',
      '.git/HEAD',
      '.dart_tool/package_config.json',
    ]) {
      File('${from.path}/$file')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(file);
    }
    final into = temp('gleon_consumer_into_');

    copyPackage(from, into);

    final copied =
        into
            .listSync(recursive: true)
            .whereType<File>()
            // Relative by URI segments: Windows lists paths with `\`.
            .map(
              (file) => file.uri.pathSegments
                  .skip(into.uri.pathSegments.length - 1)
                  .join('/'),
            )
            .toList()
          ..sort();
    expect(copied, [
      'hook/build.dart',
      'lib/gleon.dart',
      'lib/src/core/native/gleon_ffi.dart',
      'native/gleon_ref',
      'pubspec.yaml',
    ]);
    expect(
      File('${into.path}/pubspec.yaml').readAsStringSync(),
      'pubspec.yaml',
    );
    expect(nameOf(File('${from.path}/lib/gleon.dart')), 'gleon.dart');
    expect(nameOf(Directory('${from.path}/lib')), 'lib');
  });

  test('writes a consumer app of the package without any gleon config', () {
    final app = temp('gleon_consumer_app_');
    final package = Directory('/tmp/the package');

    writeConsumerApp(
      app,
      package: package,
      releaseUrl: Uri.parse('http://127.0.0.1:4321/'),
    );

    final pubspec = File('${app.path}/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('sdk: ^3.0.0'));
    expect(pubspec, contains('    path: ${package.path}\n'));
    expect(pubspec, contains('release_url: http://127.0.0.1:4321/'));
    expect(pubspec, contains('uses-material-design: true'));
    expect(
      File('${app.path}/test/flutter_test_config.dart').readAsStringSync(),
      contains('loadAppFonts()'),
    );
    final test = File('${app.path}/test/number_test.dart').readAsStringSync();
    expect(test, contains("matchesGoldenFile('$consumerGolden')"));
    expect(test, isNot(contains('const .')), reason: 'language version 3.0');
    expect(
      File('${app.path}/test/number.dart').readAsStringSync(),
      contains("const number = '42';"),
    );
    writeNumber(app, '43');
    expect(
      File('${app.path}/test/number.dart').readAsStringSync(),
      contains("const number = '43';"),
    );
    expect(Directory('${app.path}/.gleon').existsSync(), isFalse);
  });

  test(
    'a stray home config is written once and removed with its directory',
    () {
      final home = temp('gleon_consumer_home_');
      final stray = StrayHomeConfig.write(home.path);

      expect(stray.file.path, '${home.path}/.gleon/gleon.yaml');
      expect(stray.isDirCreated, isTrue);
      expect(stray.file.readAsStringSync(), isNot(contains('screenshots')));
      expect(
        () => StrayHomeConfig.write(home.path),
        throwsA(isA<CheckFailure>()),
        reason: 'never touches an existing config',
      );

      stray.remove();

      expect(Directory('${home.path}/.gleon').existsSync(), isFalse);
    },
  );

  test('phrases are found across the line wraps of flutter test', () {
    const wrapped =
        'Which: Golden "goldens/number.png": text up to 72% of a tile\n'
        'differs (gleon exact, text ≤\n5.00% per tile).';
    expect(hasPhrase(wrapped, 'text ≤ 5.00% per tile'), isTrue);
    expect(hasPhrase(wrapped, 'text up to'), isTrue);
    expect(hasPhrase(wrapped, 'text up to 73%'), isFalse);
  });

  test('a failed check names its reason', () {
    check('holds', isMet: true);
    expect(
      () => check('the sky is green', isMet: false),
      throwsA(
        isA<CheckFailure>().having(
          (failure) => failure.message,
          'message',
          'check failed: the sky is green',
        ),
      ),
    );
  });
}

/// Deletes [dir] unless something deleted it already.
void _deleteIfLeft(Directory dir) {
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}
