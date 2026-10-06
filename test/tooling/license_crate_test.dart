import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/src/license_crate.dart';

void main() {
  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_crate_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  String tempPath() => (temp ?? .systemTemp).path;

  /// A crate directory with [files] (name to content) and the `cargo
  /// metadata` package describing it.
  Map<String, Object?> package({
    Map<String, String> files = const {},
    String? licenseFile,
    bool hasLicense = true,
  }) {
    final root = Directory('${tempPath()}/crate')..createSync();
    File('${root.path}/Cargo.toml').writeAsStringSync('[package]');
    for (final MapEntry(key: name, value: content) in files.entries) {
      File('${root.path}/$name')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    return {
      'license': ?(hasLicense ? 'MIT' : null),
      'license_file': ?licenseFile,
      'manifest_path': '${root.path}/Cargo.toml',
      'name': 'demo',
      'repository': 'https://example.com/demo',
      'version': '1.2.3',
    };
  }

  test('cargo tree lines name the linked crates once', () {
    const tree = '''
gleon-ffi v0.1.0 (/work/gleon/gleon-ffi)
image v0.25.6
png v0.18.0
image v0.25.6 (*)
''';
    expect(LicenseCrate.treeLabels(tree), {
      'gleon-ffi 0.1.0',
      'image 0.25.6',
      'png 0.18.0',
    });
  });

  test('a license that needs no notice is found in the expression', () {
    LicenseCrate crate(String? license) => .new(
      license: license,
      name: 'demo',
      repository: null,
      texts: const [],
      version: '1.0.0',
    );

    expect(crate('Zlib OR MIT OR Apache-2.0').noticeFree, 'Zlib');
    expect(crate('Unlicense/MIT').noticeFree, 'Unlicense');
    expect(crate('MIT OR Apache-2.0').noticeFree, isNull);
    expect(crate(null).noticeFree, isNull);
  });

  test('license files are read once, also when named twice', () {
    final crate = LicenseCrate.of(
      package(
        files: {'COPYING': 'copying', 'LICENSE-MIT': 'MIT text\r\n'},
        licenseFile: './LICENSE-MIT',
      ),
    );
    expect(crate?.texts, ['copying', 'MIT text']);
    expect(crate?.label, 'demo 1.2.3');
  });

  test('a license file outside the scanned names is read too', () {
    final crate = LicenseCrate.of(
      package(
        files: {'docs/terms.txt': 'terms'},
        licenseFile: 'docs/terms.txt',
      ),
    );
    expect(crate?.texts, ['terms']);
  });

  test('a crate with only a license file is shown with it', () {
    final crate = LicenseCrate.of(
      package(
        files: {'LICENSE': 'custom'},
        licenseFile: 'LICENSE',
        hasLicense: false,
      ),
    );
    expect(crate?.license, isNull);
    expect(crate?.shownLicense, 'see license file');
  });

  test('a missing license file names the crate and the path', () {
    expect(
      () => LicenseCrate.of(package(licenseFile: 'LICENSE.txt')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('demo 1.2.3'), contains('LICENSE.txt')),
        ),
      ),
    );
  });

  test('a crate without license and license file is refused', () {
    expect(
      () => LicenseCrate.of(package(hasLicense: false)),
      throwsA(isA<FormatException>()),
    );
  });

  test('the linked crates come from cargo metadata, sorted', () {
    final metadata = {
      'packages': [
        package(),
        {...package(), 'name': 'alpha'},
        {...package(), 'name': 'unused'},
      ],
    };

    final linked = LicenseCrate.linked(metadata, {'demo 1.2.3', 'alpha 1.2.3'});
    expect(
      [for (final crate in linked) crate.label],
      ['alpha 1.2.3', 'demo 1.2.3'],
    );
    expect(
      () => LicenseCrate.linked(metadata, {'demo 1.2.3', 'missing 0.1.0'}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('missing 0.1.0'),
        ),
      ),
    );
  });
}
