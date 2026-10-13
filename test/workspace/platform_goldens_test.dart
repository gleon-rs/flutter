import 'dart:io';

import 'package:gleon/gleon.dart';

import '../helpers/caption.dart';
import '../helpers/golden_updates.dart';
import '../helpers/workspace_sandbox.dart';

// `fallback_platform` names the platform that tracks regressions: there text
// is compared by default (0.05 of a tile) and `--update-goldens` writes the
// goldens. Any other platform compares the same goldens with text ignored by
// default, and its updates write no golden: one that would change fails. An
// explicit text tolerance applies everywhere. The goldens are recorded inside
// the tests, so they pass on every OS, whatever flags the run was started
// with.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('on the fallback platform a changed digit fails', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml(hostPlatform));
    await _record(tester, sandbox);
    await tester.pumpWidget(const Caption(digits: '0123456780'));
    final message = await _compare(sandbox);
    final report = sandbox.readCase(_name);

    // Only text failed: the reason names no other pixels.
    expect(message, contains('": text up to'));
    expect(message, contains('text ≤ 5.00% per tile).'));
    expect(report['golden'], containsPair('path', 'test/${Caption.golden}'));
    expect(report['golden'], isNot(contains('fallback')));

    final textOff = await _compare(sandbox, textTolerance: 1);

    expect(textOff, isNull, reason: 'an explicit 1 turns text comparison off');
  });

  testWidgets('an unknown fallback platform is a config error', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml('macos-arm64'));
    await tester.pumpWidget(const Caption());
    final compared = await _compare(sandbox);
    final updated = await withGoldenUpdates(
      () => sandbox.matcher(Caption.golden).matchAsync(Caption.finder),
    );

    const error = "fallback_platform: architecture 'arm64'";
    expect(compared, contains(error));
    // The engine's message, not an exception of the test framework.
    expect(updated, contains(error));
    expect(
      () => sandbox.goldenBytes(Caption.golden),
      throwsA(isA<FileSystemException>()),
      reason: 'nothing is written',
    );
  });

  testWidgets('another platform compares the golden with text ignored', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml(hostPlatform));
    await _record(tester, sandbox);
    sandbox.writeConfig(_yaml(foreignPlatform));

    await tester.pumpWidget(const Caption(digits: '0123456780'));
    final digit = await _compare(sandbox);
    final golden = sandbox.readCase(_name)['golden'];

    expect(digit, isNull, reason: 'text of another OS is ignored');
    expect(golden, containsPair('path', 'test/${Caption.golden}'));
    expect(golden, containsPair('fallback', 'test/${Caption.golden}'));
    expect(
      sandbox.artifactsOf(_name).existsSync(),
      isFalse,
      reason: 'a pass keeps nothing',
    );

    await tester.pumpWidget(const Caption(shift: 24));
    final shifted = await _compare(sandbox);

    expect(shifted, startsWith('Golden "${Caption.golden}": '));
    expect(
      shifted,
      contains(
        'Compared with the $foreignPlatform golden, text ignored: this '
        'workspace tracks regressions on $foreignPlatform.',
      ),
    );
  });

  testWidgets('another platform updates only goldens that would not change', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml(hostPlatform));
    await _record(tester, sandbox);
    final recorded = sandbox.goldenBytes(Caption.golden);
    sandbox.writeConfig(_yaml(foreignPlatform));
    final note =
        'gleon: the golden was not updated: this workspace tracks regressions '
        'on $foreignPlatform';
    void expectUntouched() {
      // ignore: use-existing-variable, read again after each update.
      expect(sandbox.goldenBytes(Caption.golden), recorded);
      expect(
        Directory('${sandbox.dir.path}/goldens/$hostPlatform').existsSync(),
        isFalse,
        reason: 'no folder of this platform',
      );
    }

    await tester.pumpWidget(const Caption(digits: '0123456780'));
    final digit = await _update(sandbox);

    expect(digit, isNull, reason: 'only text changed: nothing to write');
    expectUntouched();

    await tester.pumpWidget(const Caption(shift: 24));
    final shifted = await _update(sandbox);

    expect(shifted, contains('text ignored).'));
    expect(shifted, contains(note));
    expect(
      shifted,
      predicate<String>(
        (message) => 'tracks regressions on'.allMatches(message).length == 1,
        'names the platform once, in the note',
      ),
    );
    expectUntouched();

    File('${sandbox.dir.path}/${Caption.golden}').deleteSync();
    final missing = await _update(sandbox);

    expect(missing, contains('non-existent file'));
    expect(missing, contains(note));
    expect(File('${sandbox.dir.path}/${Caption.golden}').existsSync(), isFalse);
  });
}

const _name = 'test/goldens/caption';

String _yaml(String fallbackPlatform) =>
    '''
required_version: ">=0.1.0"
fallback_platform: $fallbackPlatform
screenshots:
  - include: "test/goldens/**/*.png"
    mode: pixel
    diff: { threshold: 0 }
metrics: { enabled: true, console: false }
''';

/// Records the golden of an unchanged [Caption] (`--update-goldens`).
Future<void> _record(WidgetTester tester, WorkspaceSandbox sandbox) async {
  await tester.pumpWidget(const Caption());
  await withGoldenUpdates(
    () => expectLater(Caption.finder, sandbox.matcher(Caption.golden)),
  );
}

/// The failure of updating the golden with the pumped [Caption]
/// (`--update-goldens`), or null.
Future<String?> _update(WorkspaceSandbox sandbox) => withGoldenUpdates(
  () => sandbox.matcher(Caption.golden).matchAsync(Caption.finder),
);

/// The failure of comparing the pumped [Caption] with its golden, or null.
Future<String?> _compare(WorkspaceSandbox sandbox, {double? textTolerance}) =>
    withGoldenUpdates(
      () => sandbox
          .matcher(Caption.golden, textTolerance: textTolerance)
          .matchAsync(Caption.finder),
      isUpdating: false,
    );
