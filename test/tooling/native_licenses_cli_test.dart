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
      [
        '-c',
        'user.name=gleon',
        '-c',
        'user.email=gleon@example.com',
        'commit',
        '--quiet',
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
