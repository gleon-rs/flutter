import 'dart:typed_data';

import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/flutter/gleon_file_comparator.dart';
import 'package:gleon/src/flutter/gleon_golden_comparator.dart';

/// A [GleonFileComparator] comparing in its own [session] (workspace and
/// environment) instead of the process's, so a test never depends on the
/// environment it runs in: what harness users get, hermetic.
final class SessionFileComparator extends GleonFileComparator {
  /// Creates the comparator of [testFile] comparing in [session].
  SessionFileComparator(super.testFile, this.session);

  /// The session of every comparison.
  final GleonSession session;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) =>
      GleonGoldenComparator(this, session: session).compare(imageBytes, golden);

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      GleonGoldenComparator(this, session: session).update(golden, imageBytes);
}
