import 'dart:io';
import 'dart:ui';

import 'package:gleon/gleon.dart';
import 'package:gleon/src/flutter/gleon_matches_golden_file.dart';

import '../helpers/swatch.dart';
import '../helpers/workspace_sandbox.dart';

void main() {
  setUp(WorkspaceSandbox.withoutWorkspace);

  GleonMatchesGoldenFile matcher() => .new(
    Uri.parse(Swatch.golden),
    null,
    session: sessionWithoutWorkspace(metrics: '1'),
  );

  testWidgets('behaves like Flutter and writes no gleon files', (tester) async {
    await tester.pumpWidget(const Swatch());
    await expectLater(Swatch.finder, matcher());

    final written = WorkspaceSandbox.current().root
        .listSync(recursive: true)
        .where((entry) => entry.uri.pathSegments.contains('.gleon'));
    expect(written, isEmpty, reason: 'no .gleon anywhere in the sandbox');
    expect(Directory('.gleon').existsSync(), isFalse);
  });

  testWidgets('failures point at .gleon/gleon.yaml tolerances', (tester) async {
    await tester.pumpWidget(const Swatch(accent: Color(0xFF4CAF50)));
    final message = await matcher().matchAsync(Swatch.finder);

    expect(message, contains('Tip: tolerances can be set per golden in'));
    expect(message, contains('.gleon/gleon.yaml'));
  });
}
