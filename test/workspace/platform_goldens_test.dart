import 'dart:io';

import 'package:gleon/gleon.dart';

import '../helpers/caption.dart';
import '../helpers/golden_updates.dart';
import '../helpers/workspace_sandbox.dart';

// `fallback_platform` names the platform of the shared goldens: there text is
// compared by default (0.05 of a tile). Any other platform records its own
// goldens in `goldens/<os>-<arch>/` and, until it has one, compares the shared
// golden with text ignored by default. An explicit text tolerance applies
// everywhere. The goldens are recorded inside the tests, so they pass on every
// OS, whatever flags the run was started with.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('on the platform of the goldens a changed digit fails', (
    tester,
  ) async {
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

  testWidgets(
    'another platform compares the shared golden, then records its own',
    (tester) async {
      final sandbox = WorkspaceSandbox.create(_yaml(hostPlatform));
      await _record(tester, sandbox);
      final recorded = sandbox.goldenBytes(Caption.golden);
      sandbox.writeConfig(_yaml(foreignPlatform));
      final own = 'goldens/$hostPlatform/caption.png';
      const digit = Caption(digits: '0123456780');

      await tester.pumpWidget(digit);
      final againstShared = await _compare(sandbox);
      final sharedGolden = sandbox.readCase(_name)['golden'];

      expect(againstShared, isNull, reason: 'text of another OS is ignored');
      expect(sharedGolden, containsPair('fallback', 'test/${Caption.golden}'));
      expect(sharedGolden, containsPair('path', 'test/$own'));
      // The pass differs from the shared golden, so it keeps its candidate:
      // `gleon approve` can make it this platform's own golden.
      expect(
        File('${sandbox.artifactsOf(_name).path}/candidate.png').existsSync(),
        isTrue,
      );

      await _record(tester, sandbox);
      expect(sandbox.goldenBytes(own), isNotEmpty);
      expect(
        // ignore: use-existing-variable, read again after the update.
        sandbox.goldenBytes(Caption.golden),
        recorded,
        reason: 'the shared golden is left alone',
      );

      await tester.pumpWidget(digit);
      final againstOwn = await _compare(sandbox);

      expect(againstOwn, startsWith('Golden "$own": '));
      expect(againstOwn, contains('text ≤ 5.00% per tile).'));
      expect(sandbox.readCase(_name)['golden'], isNot(contains('fallback')));
    },
  );
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

/// The failure of comparing the pumped [Caption] with its golden, or null.
Future<String?> _compare(WorkspaceSandbox sandbox, {double? textTolerance}) =>
    withGoldenUpdates(
      () => sandbox
          .matcher(Caption.golden, textTolerance: textTolerance)
          .matchAsync(Caption.finder),
      isUpdating: false,
    );
