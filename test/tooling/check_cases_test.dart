import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_cases_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  String tempPath() => (temp ?? .systemTemp).path;

  /// Writes the case report [path] of the runs directory.
  void write(String path, String content) {
    File('${tempPath()}/cases/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// A report of macOS that compared the shared golden [name]`.png` with
  /// text.
  String report(String name) => json.encode({
    'comparison': {'text_tolerance': 0.05},
    'golden': {'path': '$name.png'},
    'name': name,
    'outcome': 'match',
    'platform': {'arch': 'aarch64', 'os': 'macos'},
    'run_id': 'run-1',
    'schema_version': 3,
  });

  Future<ProcessResult> checkCases(List<String> args) {
    final script = ['bin/check_cases.dart', tempPath(), ...args];

    // `dart` of the Flutter SDK; a batch file on Windows.
    return Process.run('dart', script, runInShell: Platform.isWindows);
  }

  test('a run as expected passes', () async {
    write('macos-aarch64/test/goldens/a.json', report('test/goldens/a'));
    write('macos-aarch64/test/goldens/b.json', report('test/goldens/b'));

    final result = await checkCases([
      '--fallback-platform',
      'macos-aarch64',
      '--min-cases',
      '2',
      '--run-id',
      'run-1',
    ]);
    expect(result.stdout, contains('2 case reports as expected.'));
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('every file is checked, and any problem fails the run', () async {
    write('a.json', '{"golden": ');
    write('b.json', '[]');
    write('macos-aarch64/test/goldens/c.json', report('test/goldens/c'));
    // The flat layout of an older gleon.
    write('test/goldens/d.json', report('test/goldens/d'));

    final result = await checkCases([
      '--fallback-platform',
      'macos-aarch64',
      '--min-cases',
      '5',
      '--run-id',
      'run-2',
    ]);
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      allOf(
        contains('a.json: invalid JSON ('),
        contains('b.json: not a case report'),
        contains('c.json: run_id run-1, expected run-2'),
        contains(
          'd.json: lies at test/goldens/d.json, expected '
          'macos-aarch64/test/goldens/d.json',
        ),
        contains('4 case reports, expected at least 5.'),
      ),
    );
    expect(result.stdout, contains('FAIL'));
  });

  test('a runs directory and one platform option are required', () async {
    final result = await checkCases(['--own', '--fallback-platform', 'x']);
    expect(result.exitCode, 64);
    expect(result.stderr, contains('one of --fallback-platform or --own'));
  });
}
