import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/flutter/flutter_session.dart';
import 'package:gleon/src/flutter/gleon_golden_comparator.dart';

import '../../helpers/workspace_sandbox.dart';

void main() {
  group('FlutterSession', () {
    test('the test name is read from the running test', () {
      expect(
        FlutterSession.currentTestName,
        'FlutterSession the test name is read from the running test',
      );
    });

    test('outside a test there is no test name', () {
      expect(Zone.root.run(() => FlutterSession.currentTestName), isNull);
    });

    test('the recorded tool version is the pubspec version', () {
      final pubspec = File('pubspec.yaml').readAsLinesSync();

      expect(pubspec, contains('version: ${FlutterSession.packageVersion}'));
    });

    test('failure artifacts are named like Flutter names them', () {
      final GleonIntegration(
        :candidateArtifact,
        :diffArtifact,
        :goldenArtifact,
        :renderer,
        :tool,
      ) = FlutterSession.integration;

      expect(tool, 'gleon_flutter');
      expect(renderer, startsWith('flutter-'));
      expect(
        [goldenArtifact, candidateArtifact, diffArtifact],
        [
          '{name}_masterImage.png',
          '{name}_testImage.png',
          '{name}_gleonDiff.png',
        ],
      );
    });
  });

  group('GleonGoldenComparator', () {
    test('updates through a custom comparator fail like comparisons', () async {
      final custom = _RecordingComparator();
      final comparator = GleonGoldenComparator(
        custom,
        session: sessionWithoutWorkspace(),
      );
      final bytes = Uint8List.fromList(const [1, 2, 3]);

      await expectLater(
        comparator.update(Uri.parse('goldens/a.png'), bytes),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            allOf(
              contains('needs a LocalFileComparator'),
              contains('_RecordingComparator'),
              // The ways out: no custom comparator, or Flutter's matcher.
              contains('remove the custom goldenFileComparator'),
              contains('flutter_test_config.dart'),
              contains("import 'package:flutter_test/flutter_test.dart' as ft"),
              contains('ft.matchesGoldenFile'),
            ),
          ),
        ),
      );
      expect(custom.updates, isEmpty, reason: 'nothing written behind gleon');
      expect(
        comparator.getTestUri(Uri.parse('a.png'), 2),
        Uri.parse('a.2.png'),
      );
    });

    test('failures that are gleon bugs ask for a report', () async {
      final comparator = GleonGoldenComparator(
        LocalFileComparator(
          Uri.file('${Directory.systemTemp.path}/a_test.dart'),
        ),
        session: GleonSession(
          // Broken on purpose: a contract breach of this package.
          integration: const GleonIntegration(
            tool: 'gleon_flutter',
            toolVersion: '0.1.0',
            goldenArtifact: 'master.png',
            candidateArtifact: '{name}_testImage.png',
            diffArtifact: '{name}_gleonDiff.png',
          ),
          hasWorkspaces: false,
          environment: const GleonEnvironment(),
        ),
      );

      await expectLater(
        comparator.compare(Uint8List(0), Uri.parse('goldens/a.png')),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            allOf(
              contains('must contain `{name}`'),
              endsWith(GleonGoldenComparator.bugHint),
            ),
          ),
        ),
      );
    });
  });
}

final class _RecordingComparator extends GoldenFileComparator {
  final updates = <(Uri, Uint8List)>[];

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async =>
      updates.add((golden, imageBytes));
}
