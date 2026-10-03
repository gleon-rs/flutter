import 'dart:io';
import 'dart:ui';

import 'package:gleon/gleon.dart';

import '../helpers/blob.dart';
import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

const _yaml = '''
required_version: ">=0.1.0"
exclude: "test/goldens/excluded_*.png"
screenshots:
  - include: "test/goldens/**/*.png"
    mode: ssim
    diff: { min_similarity: 0.8, color_tolerance: 8 }
  - include: "test/masked/*.png"
    diff: { threshold: 0 }
    masks:
      - path: "**/swatch.png"
        zones: [{ x: 0, y: 0, width: "25%", height: 20 }]
''';

void main() {
  testWidgets("the golden's yaml rule sets the tolerance", (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Blob(offset: 0.3));

    await expectLater(Blob.finder, sandbox.matcher(Blob.golden));
  });

  testWidgets('a call argument overrides the yaml rule', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Blob(offset: 0.3));
    final message = await sandbox
        .matcher(Blob.golden, tolerance: const .exact())
        .matchAsync(Blob.finder);

    expect(message, contains('(gleon exact)'));
  });

  testWidgets('excluded and unmatched goldens compare exactly', (tester) async {
    final sandbox = WorkspaceSandbox.create(
      _yaml,
      extraGoldens: const {
        'goldens/excluded_blob.png': 'blob.png',
        'other/blob.png': 'blob.png',
      },
    );
    await tester.pumpWidget(const Blob(offset: 0.3));

    for (final key in ['goldens/excluded_blob.png', 'other/blob.png']) {
      final message = await sandbox.matcher(key).matchAsync(Blob.finder);

      expect(message, contains('(gleon exact)'), reason: key);
    }
  });

  testWidgets('yaml masks, percentages included, hide changes', (tester) async {
    final sandbox = WorkspaceSandbox.create(
      _yaml,
      extraGoldens: const {'masked/swatch.png': 'swatch.png'},
    );
    await tester.pumpWidget(const Swatch(dot: Swatch.dotOffset));

    await expectLater(Swatch.finder, sandbox.matcher('masked/swatch.png'));
  });

  testWidgets('call regions add to the yaml masks', (tester) async {
    final sandbox = WorkspaceSandbox.create(
      _yaml,
      extraGoldens: const {'masked/swatch.png': 'swatch.png'},
    );
    // The dot is outside the yaml mask, only the call's region hides it.
    await tester.pumpWidget(const Swatch(dot: Offset(60, 40)));
    await expectLater(
      Swatch.finder,
      sandbox.matcher(
        'masked/swatch.png',
        ignoreRegions: const [Rect.fromLTWH(60, 40, 1, 1)],
      ),
    );
    final message = await sandbox
        .matcher('masked/swatch.png')
        .matchAsync(Swatch.finder);

    // Masked pixels are neither compared nor counted: 6000 minus the yaml
    // mask's 500.
    expect(message, contains('1 of 5500px'));
  });

  testWidgets('an invalid config fails with its path and the parser text', (
    tester,
  ) async {
    final sandbox = WorkspaceSandbox.create(
      "required_version: '>=0.1.0'\nscreenshots: []\ncolour: red\n",
    );
    await tester.pumpWidget(const Swatch());
    final message = await sandbox
        .matcher(Swatch.golden)
        .matchAsync(Swatch.finder);

    // With the separators of the platform, like every path gleon shows.
    final config = [
      sandbox.root.path,
      '.gleon',
      'gleon.yaml',
    ].join(Platform.pathSeparator);

    expect(message, contains('gleon: $config: '));
    expect(message, contains('unknown field `colour`'));
  });

  testWidgets('a golden name the CLI rejects fails strictly', (tester) async {
    final sandbox = WorkspaceSandbox.create(
      _yaml,
      extraGoldens: const {'goldens/Bad Name.png': 'swatch.png'},
    );
    await tester.pumpWidget(const Swatch());
    final message = await sandbox
        .matcher('goldens/Bad%20Name.png')
        .matchAsync(Swatch.finder);

    expect(message, contains('not a valid gleon test path'));
  });

  testWidgets('mismatches in a workspace carry no .gleon hint', (tester) async {
    final sandbox = WorkspaceSandbox.create(_yaml);
    await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
    final message = await sandbox
        .matcher(Swatch.golden)
        .matchAsync(Swatch.finder);

    expect(message, isNot(contains('Tip:')));
  });
}
