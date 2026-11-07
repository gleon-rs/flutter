import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_licenses_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  String tempPath() => (temp ?? .systemTemp).path;

  Future<ProcessResult> git(List<String> args) =>
      Process.run('git', args, workingDirectory: tempPath());

  /// A committed gleon checkout with the inputs of the library.
  Future<void> checkout() async {
    final files = {
      'Cargo.lock': '# lock',
      'Cargo.toml': '[workspace]',
      'gleon-ffi/Cargo.toml': '[package]',
      'gleon-ffi/src/lib.rs': '// Rust',
    };
    for (final MapEntry(key: path, value: content) in files.entries) {
      File('${tempPath()}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }
    for (final args in [
      ['init', '--quiet'],
      ['add', '.'],
      // Whatever the developer's git configuration signs or hooks.
      [
        '-c',
        'user.name=gleon',
        '-c',
        'user.email=gleon@example.com',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'core.hooksPath=/dev/null',
        'commit',
        '--quiet',
        '--no-verify',
        '-m',
        'gleon',
      ],
    ]) {
      final result = await git(args);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
  }

  Future<ProcessResult> nativeLicenses() => Process.run(
    'dart',
    ['bin/native_licenses.dart', '--gleon-repo', tempPath(), '--check'],
    // `dart` of the Flutter SDK; a batch file on Windows.
    runInShell: Platform.isWindows,
  );

  test('a directory that is no gleon checkout is refused', () async {
    final result = await nativeLicenses();
    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains(
        'native_licenses: ${tempPath()} (--gleon-repo) is not a gleon '
        'checkout; pass one with --gleon-repo.',
      ),
    );
  });

  // A stale variable is fixed where it is set, so the failure names it.
  test(r'a $GLEON_REPO that is no gleon checkout is named', () async {
    final result = await Process.run(
      'dart',
      ['bin/native_licenses.dart', '--check'],
      environment: {'GLEON_REPO': tempPath()},
      runInShell: Platform.isWindows,
    );
    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains('native_licenses: ${tempPath()} (\$GLEON_REPO) is not'),
    );
  });

  test('a checkout with uncommitted library inputs is refused', () async {
    await checkout();
    File('${tempPath()}/Cargo.lock').writeAsStringSync('# changed');

    final result = await nativeLicenses();
    expect(result.exitCode, 64);
    expect(result.stderr, contains('uncommitted changes'));
  });

  test('a clean checkout of another commit is refused for the pin', () async {
    await checkout();

    final result = await nativeLicenses();
    expect(result.exitCode, 64);
    expect(
      result.stderr,
      allOf(contains('pins'), isNot(contains('uncommitted'))),
    );
  });
}
