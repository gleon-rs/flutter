import 'package:flutter_test/flutter_test.dart';

import '../../bin/src/license_crate.dart';
import '../../bin/src/native_licenses.dart';

void main() {
  const commit = '18bc3075e002360815ae856d0a854cb6a62fa5a5';

  LicenseCrate crate(
    String name, {
    String license = 'MIT',
    List<String> texts = const ['MIT text'],
    bool hasLicense = true,
  }) => .new(
    license: hasLicense ? license : null,
    name: name,
    repository: 'https://example.com/$name',
    texts: texts,
    version: '1.0.0',
  );

  test('the header names the gleon commit it was generated for', () {
    final markdown = NativeLicenses([crate('a')], gleonCommit: commit).markdown;
    expect(markdown, startsWith('# Licenses of the native library\n'));
    expect(markdown, contains('for gleon $commit'));
  });

  test('a table row per crate, then each text once with its crates', () {
    final crates = [
      crate('a'),
      crate('b'),
      crate('c', license: 'Zlib OR MIT', texts: const []),
      crate('d', texts: const ['custom'], hasLicense: false),
    ];
    final markdown = NativeLicenses(crates, gleonCommit: commit).markdown;
    expect(
      markdown,
      allOf(
        contains('| a | 1.0.0 | MIT | https://example.com/a |\n'),
        contains(
          '| c | 1.0.0 | Zlib OR MIT (Zlib, which needs no notice) | '
          'https://example.com/c |\n',
        ),
        contains('| d | 1.0.0 | see license file | https://example.com/d |\n'),
        contains('| Rust standard library | (toolchain) | MIT OR Apache-2.0 |'),
        contains('### a 1.0.0, b 1.0.0\n\n```text\nMIT text\n```\n'),
        contains('### d 1.0.0\n'),
      ),
    );
  });

  test('crates without texts need a license that needs no notice', () {
    final crates = [
      crate('a', texts: const []),
      crate('b', license: '0BSD', texts: const []),
    ];
    final licenses = NativeLicenses(crates, gleonCommit: commit);
    expect(licenses.unlicensed, ['a 1.0.0']);
  });

  test('a fence is longer than any backtick run of its text', () {
    expect(NativeLicenses.fenceLength('plain'), 3);
    expect(NativeLicenses.fenceLength('a ```` b ` c'), 5);
  });
}
