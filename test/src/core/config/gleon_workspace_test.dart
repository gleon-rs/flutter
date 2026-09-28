import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/config/gleon_config_exception.dart';
import 'package:gleon/src/core/config/gleon_workspace.dart';

/// A fresh temp directory (symbolic links resolved), deleted after the test.
Directory _tempDir([String prefix = 'gleon_find_']) {
  final dir = Directory(
    Directory.systemTemp.createTempSync(prefix).resolveSymbolicLinksSync(),
  );
  addTearDown(() => dir.deleteSync(recursive: true));

  return dir;
}

void main() {
  test('walks up to the nearest .gleon/gleon.yaml, like the CLI', () {
    final temp = _tempDir();
    final nested = Directory('${temp.path}/a/b/c')..createSync(recursive: true);
    File('${temp.path}/.gleon/gleon.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync("required_version: '>=0.1.0'\n");
    final workspace = GleonWorkspace.find(nested);

    expect(workspace?.root.path, temp.path);
    expect(workspace?.configText, "required_version: '>=0.1.0'\n");
    expect(workspace?.casesDir.path, '${temp.path}/.gleon/runs/latest/cases');
  });

  test('a .gleon directory without gleon.yaml is not a workspace', () {
    final temp = _tempDir();
    Directory('${temp.path}/.gleon').createSync();

    expect(GleonWorkspace.find(temp)?.root.path, isNot(temp.path));
  });

  test('golden paths are workspace-relative with / separators', () {
    final temp = _tempDir();
    File('${temp.path}/.gleon/gleon.yaml').createSync(recursive: true);
    final golden = File('${temp.path}/test/goldens/a.png')
      ..createSync(recursive: true);
    final outside = File('${_tempDir('gleon_outside_').path}/outside.png')
      ..createSync();
    final workspace = GleonWorkspace.find(temp);

    expect(workspace?.relativePath(golden), 'test/goldens/a.png');
    expect(workspace?.relativePath(outside), isNull);
  });

  test('an unreadable config fails with its path', () {
    final temp = _tempDir();
    final config = File('${temp.path}/.gleon/gleon.yaml')
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [0xff, 0xfe, 0x00]);

    expect(
      () => GleonWorkspace.find(temp),
      throwsA(
        isA<GleonConfigException>()
            .having((error) => error.configPath, 'path', config.path)
            .having(
              (error) => error.message,
              'message',
              contains('cannot read'),
            ),
      ),
    );
  });
}
