import 'dart:io';
import 'dart:typed_data';

import 'package:gleon/gleon.dart';

import '../helpers/golden_updates.dart';
import '../helpers/workspace_sandbox.dart';

const _golden = 'goldens/incomplete.png';

/// Bytes that are no complete PNG: no comparison can decode them, so they
/// never pass as identical to themselves, and `--update-goldens` never
/// records them.
void main() {
  setUp(WorkspaceSandbox.withoutWorkspace);

  File golden() => .new('${WorkspaceSandbox.current().dir.path}/$_golden');

  final complete = File('$goldenSource/swatch.png').readAsBytesSync();
  // Cut inside the image data: the header is whole, the end is gone.
  final truncated = Uint8List.sublistView(complete, 0, complete.length - 20);
  final noPng = Uint8List.fromList('not a png'.codeUnits);

  for (final (name, bytes) in [('no PNG', noPng), ('a cut PNG', truncated)]) {
    test('$name is never identical to itself', () async {
      golden()
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);

      final message = await matchesGoldenFile(_golden).matchAsync(bytes);

      expect(message, contains('gleon could not compare: golden image'));
    });

    test('--update-goldens never records $name', () async {
      golden()
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(complete);

      final message = await withGoldenUpdates(
        () => matchesGoldenFile(_golden).matchAsync(bytes),
      );

      expect(
        message,
        contains(
          'gleon cannot record it: the candidate is not a complete PNG.',
        ),
      );
      expect(golden().readAsBytesSync(), complete);
    });
  }
}
