import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

import '../core/config/gleon_session.dart';
import 'gleon_golden_comparator.dart';

/// A `goldenFileComparator` backed by the gleon engine, for golden harnesses
/// (alchemist, golden_toolkit, …) and tests that call `flutter_test`'s own
/// `matchesGoldenFile`. Install it once, in `test/flutter_test_config.dart`:
///
/// ```dart
/// import "dart:async";
///
/// import "package:gleon/gleon.dart";
///
/// Future<void> testExecutable(FutureOr<void> Function() testMain) async {
///   goldenFileComparator = GleonFileComparator.fromExisting(
///     goldenFileComparator,
///   );
///   await testMain();
/// }
/// ```
///
/// Goldens resolve like with Flutter's [LocalFileComparator] (relative to the
/// test file); tolerances and masks come from the golden's
/// `.gleon/gleon.yaml` rule, else the comparison is exact; failures and
/// `--update-goldens` behave like with gleon's own `matchesGoldenFile`.
///
/// A best-effort path: a comparator only gets PNG bytes, so text is
/// compared like every other pixel (no text boxes) and the PNG of every
/// candidate is encoded by Flutter first. gleon's `matchesGoldenFile` with a
/// widget (`Finder`) compares the raw pixels with the boxes of their text and
/// is faster; it works with this comparator installed too (it only takes the
/// directory of the goldens from it).
class GleonFileComparator extends LocalFileComparator {
  /// Creates a comparator for the goldens of the test file [testFile], like
  /// [LocalFileComparator].
  GleonFileComparator(super.testFile) : _names = null, _session = null;

  /// A comparator with its own session (workspace and environment) instead
  /// of the process's, so a test never depends on the environment it runs
  /// in.
  @visibleForTesting
  GleonFileComparator.withSession(super.testFile, GleonSession this._session)
    : _names = null;

  /// Any file name in the directory of [_names]: only the directory is used.
  GleonFileComparator._naming(LocalFileComparator this._names)
    : _session = null,
      super(_names.basedir.resolve('gleon_test.dart'));

  /// A comparator for the goldens of [existing], the [LocalFileComparator]
  /// `flutter test` installs before `test/flutter_test_config.dart` runs or
  /// a subclass of it: the same directory, and the golden names of its
  /// [getTestUri] (its own comparison never runs). [existing] itself when it
  /// is a `GleonFileComparator` already.
  ///
  /// Throws an [ArgumentError] for any other comparator: it has no golden
  /// directory to take.
  factory GleonFileComparator.fromExisting(GoldenFileComparator existing) =>
      switch (existing) {
        final GleonFileComparator installed => installed,
        final LocalFileComparator local => ._naming(local),
        final other => throw ArgumentError.value(
          other,
          'existing',
          'gleon: GleonFileComparator.fromExisting takes the golden directory '
              'of a LocalFileComparator, but goldenFileComparator is '
              '${other.runtimeType}; install it from '
              'test/flutter_test_config.dart under flutter test',
        ),
      };

  /// The comparator of `fromExisting`, which names the goldens; null: this
  /// one.
  final LocalFileComparator? _names;

  /// The session of `withSession`; null: the process's.
  final GleonSession? _session;

  @override
  Uri getTestUri(Uri key, int? version) =>
      _names?.getTestUri(key, version) ?? super.getTestUri(key, version);

  /// Compares [imageBytes] (a PNG) with [golden]; throws a [TestFailure] with
  /// the engine's message unless it passes.
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) =>
      GleonGoldenComparator(
        this,
        session: _session,
      ).compare(imageBytes, golden);

  /// Writes [imageBytes] (a PNG) as [golden] through the engine (the
  /// golden of this platform, see the README's "Real text").
  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      GleonGoldenComparator(this, session: _session).update(golden, imageBytes);
}
