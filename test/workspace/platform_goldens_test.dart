import 'dart:io';

import 'package:gleon/gleon.dart';
import 'package:gleon/src/core/config/gleon_session.dart';

import '../helpers/caption.dart';
import '../helpers/golden_updates.dart';
import '../helpers/png_origin.dart';
import '../helpers/prints.dart';
import '../helpers/workspace_sandbox.dart';

// Every golden names the platform it was recorded on in its PNG: its text is
// compared there by default (0.05 of a tile) and ignored elsewhere; a golden
// without that stamp counts as recorded on `fallback_platform`. Updates record
// on any platform, but leave a golden recorded elsewhere while only its text
// differs; the `fallback_platform` records again what others recorded. The
// goldens are recorded inside the tests, so they pass on every OS, whatever
// flags the run was started with.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('on the platform of the golden a changed digit fails', (
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
    expect(report['golden'], containsPair('platform', hostPlatform));
    expect(PngOrigin.read(sandbox.goldenBytes(Caption.golden)), hostPlatform);

    final textOff = await _compare(sandbox, textTolerance: 1);

    expect(textOff, isNull, reason: 'an explicit 1 turns text comparison off');
  });

  testWidgets('without a fallback platform text is strict where recorded', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml(null));
    await _record(tester, sandbox);
    await tester.pumpWidget(const Caption(digits: '0123456780'));
    final message = await _compare(sandbox);

    expect(PngOrigin.read(sandbox.goldenBytes(Caption.golden)), hostPlatform);
    expect(message, contains('text ≤ 5.00% per tile).'));
  });

  testWidgets('an invalid GLEON_REQUIRE_CANONICAL fails every golden', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml(hostPlatform));
    await tester.pumpWidget(const Caption());
    final message = await _compare(
      sandbox,
      session: sandbox.session(requireCanonical: 'maybe'),
    );

    expect(
      message,
      contains(
        "GLEON_REQUIRE_CANONICAL must be 1, 0, true or false (got 'maybe')",
      ),
    );
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

  testWidgets('another platform ignores the text of a golden', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml(foreignPlatform));
    await _record(tester, sandbox);
    _restamp(sandbox, foreignPlatform);

    await tester.pumpWidget(const Caption(digits: '0123456780'));
    final digit = await _compare(sandbox);
    final golden = sandbox.readCase(_name)['golden'];

    expect(digit, isNull, reason: 'text of another OS is ignored');
    expect(golden, containsPair('platform', foreignPlatform));
    expect(
      sandbox.artifactsOf(_name).existsSync(),
      isFalse,
      reason: 'a pass keeps nothing',
    );

    await tester.pumpWidget(const Caption(shift: 24));
    final shifted = await _compare(sandbox);

    expect(shifted, startsWith('Golden "${Caption.golden}": '));
    expect(shifted, contains('The golden was recorded on $foreignPlatform.'));
  });

  testWidgets('another platform records goldens that change', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml(foreignPlatform));
    await _record(tester, sandbox);
    _restamp(sandbox, foreignPlatform);
    final recorded = sandbox.goldenBytes(Caption.golden);

    await tester.pumpWidget(const Caption(digits: '0123456780'));
    final digit = await _update(sandbox);

    expect(digit, isNull);
    expect(
      // ignore: use-existing-variable, read again after the update.
      sandbox.goldenBytes(Caption.golden),
      recorded,
      reason: 'only text changed: the golden stays',
    );

    await tester.pumpWidget(const Caption(shift: 24));
    final shifted = await _update(sandbox);

    expect(shifted, isNull);
    expect(
      // ignore: use-existing-variable, read again after the update.
      PngOrigin.read(sandbox.goldenBytes(Caption.golden)),
      hostPlatform,
    );
    expect(
      Directory('${sandbox.dir.path}/goldens/$hostPlatform').existsSync(),
      isFalse,
      reason: 'no folder of this platform',
    );

    await tester.pumpWidget(const Caption(digits: '0123456780', shift: 24));
    final own = await _compare(sandbox);

    expect(own, contains('text ≤ 5.00% per tile).'), reason: 'recorded here');
  });

  testWidgets('the fallback platform records again what others recorded', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(_yaml(hostPlatform));
    await _record(tester, sandbox);
    _restamp(sandbox, foreignPlatform);

    await tester.pumpWidget(const Caption(digits: '0123456780'));
    final lines = await capturePrints(
      () async => expect(
        await _compare(sandbox),
        isNull,
        reason: 'recorded elsewhere: text ignored',
      ),
    );
    expect(
      lines,
      contains(
        startsWith(
          'gleon: golden "${Caption.golden}" was recorded on $foreignPlatform',
        ),
      ),
    );
    final required = await _compare(
      sandbox,
      session: sandbox.session(requireCanonical: '1'),
    );

    expect(required, contains('GLEON_REQUIRE_CANONICAL'));

    await tester.pumpWidget(const Caption());
    await _update(sandbox);

    expect(PngOrigin.read(sandbox.goldenBytes(Caption.golden)), hostPlatform);
  });
}

/// Stamps the golden of [sandbox] as recorded on [platform].
void _restamp(WorkspaceSandbox sandbox, String platform) =>
    File('${sandbox.dir.path}/${Caption.golden}').writeAsBytesSync(
      PngOrigin.stamp(sandbox.goldenBytes(Caption.golden), platform),
    );

const _name = 'test/goldens/caption';

/// The config of the sandbox, with [fallbackPlatform] unless it is null.
String _yaml(String? fallbackPlatform) =>
    '''
required_version: ">=0.1.0"
${fallbackPlatform == null ? '# no fallback_platform' : 'fallback_platform: $fallbackPlatform'}
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
Future<String?> _compare(
  WorkspaceSandbox sandbox, {
  double? textTolerance,
  GleonSession? session,
}) => withGoldenUpdates(
  () => sandbox
      .matcher(Caption.golden, textTolerance: textTolerance, session: session)
      .matchAsync(Caption.finder),
  isUpdating: false,
);
