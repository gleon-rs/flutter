import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart' as flutter_test;

import '../core/compare/golden_tolerance.dart';
import '../core/compare/pixel_region.dart';
import '../core/compare/tolerances.dart';
import '../core/config/gleon_session.dart';
import 'flutter_session.dart';
import 'gleon_golden_comparator.dart';
import 'text_regions.dart';

/// The matcher created by `matchesGoldenFile`.
///
/// Extends Flutter's own [flutter_test.MatchesGoldenFile] for its key,
/// version and description, and matches every input itself with a
/// comparator of its own wrapping `goldenFileComparator`, which it never
/// replaces. A widget (a `Finder`) is captured like Flutter does and, like a
/// `ui.Image`, compared as raw pixels (a widget with the boxes of its text; a
/// PNG is encoded only to keep it: for a failure, or a pass against another
/// platform's golden with metrics on); bytes are compared as PNG. Written by
/// `--update-goldens` with the engine's failure as the message, like a
/// comparison.
class GleonMatchesGoldenFile extends flutter_test.MatchesGoldenFile {
  /// Creates the matcher; prefer `matchesGoldenFile`, which validates the
  /// arguments.
  const GleonMatchesGoldenFile(
    super.key,
    super.version, {
    this.tolerance,
    this.masks = const [],
    this.textTolerance,
    this.session,
  });

  /// The golden [key] of a matcher call, a [String] or a [Uri], as a [Uri].
  ///
  /// Throws an [ArgumentError] for any other type, like Flutter's matcher.
  static Uri uriOf(Object key) => switch (key) {
    Uri() => key,
    String() => .parse(key),
    _ => throw ArgumentError.value(
      key,
      'key',
      'Unexpected type for golden file: ${key.runtimeType}',
    ),
  };

  /// The requested tolerance; null means the golden's `.gleon/gleon.yaml`
  /// rule, else exact.
  final GoldenTolerance? tolerance;

  /// Regions excluded from the comparison, in whole pixels of the golden.
  final List<PixelRegion> masks;

  /// The tolerance of text, a share of a tile (0.0–1.0); null means the
  /// golden's `.gleon/gleon.yaml` rule, else the golden's default (see
  /// `matchesGoldenFile`).
  final double? textTolerance;

  /// Workspace and environment; [FlutterSession.process] when null (tests
  /// inject their own).
  final GleonSession? session;

  @override
  Future<String?> matchAsync(Object? item) async {
    // Everything global is read before the first await: a match abandoned by
    // a timed-out test may go on after the next test replaced
    // `goldenFileComparator` or the update flag. Finding the workspace may
    // throw.
    final comparator = GleonGoldenComparator(
      flutter_test.goldenFileComparator,
      tolerance: tolerance,
      masks: masks,
      textTolerance: textTolerance,
      session: session,
    );
    final _Golden golden = (
      comparator: comparator,
      isUpdate: flutter_test.autoUpdateGoldenFiles,
      uri: comparator.getTestUri(key, version),
    );
    // Flutter's order and messages: bytes (a null future falls through),
    // then images, then widgets.
    final bytes = switch (item) {
      final Future<List<int>?> pending => await pending,
      final List<int> list => list,
      _ => null,
    };

    return bytes == null
        ? await _matchOther(item, golden)
        : await _matchBytes(bytes, golden);
  }

  @override
  flutter_test.Description describe(flutter_test.Description description) {
    final text = switch (textTolerance) {
      final share? => ', ${Tolerances.describeText(share)}',
      null => _noText,
    };

    return super
        .describe(description)
        .add(' (gleon ${tolerance ?? 'default tolerance'}$text)');
  }

  static const _noText = '';

  /// Matches an image or a widget, Flutter's other inputs.
  static Future<String?> _matchOther(Object? item, _Golden golden) =>
      switch (item) {
        final Future<ui.Image?> pending => _matchImage(pending, golden),
        final ui.Image image => _matchImage(.value(image), golden),
        final flutter_test.Finder finder => _matchWidget(finder, golden),
        _ => throw AssertionError(
          'must provide a Finder, Image, Future<Image>, List<int>, or '
          'Future<List<int>>',
        ),
      };

  /// Compares PNG [bytes] with [golden], or writes them; a failure is the
  /// message in both modes. A [Uint8List] is passed as is: the native call
  /// reads it in place, synchronously, before anything else can change it.
  static Future<String?> _matchBytes(List<int> bytes, _Golden golden) async {
    final (:comparator, :isUpdate, :uri) = golden;
    final png = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      if (isUpdate) {
        await comparator.update(uri, png);
      } else {
        // Throws a TestFailure unless the golden passes.
        await comparator.compare(png, uri);
      }

      return null;
    } on flutter_test.TestFailure catch (error) {
      return error.message;
    }
  }

  /// Captures the widget of [finder] like Flutter's matcher and matches it
  /// with the boxes of its text; the same messages for a bad finder.
  static Future<String?> _matchWidget(
    flutter_test.Finder finder,
    _Golden golden,
  ) {
    final found = finder.evaluate();
    if (found.isEmpty) {
      return .value('could not be rendered because no widget was found');
    }
    final element = found.singleOrNull;
    if (element == null) return .value('matched too many widgets');
    // Before capturing (nothing to dispose if it throws) and before awaiting
    // anything: the tree must be the one captured.
    final textRegions = golden.isUpdate
        ? const <PixelRegion>[]
        : TextRegions.captured(element);

    return _matchImage(
      flutter_test.captureImage(element),
      golden,
      textRegions: textRegions,
      isOwned: true,
    );
  }

  /// Compares the image of [pending] as raw pixels with [textRegions], or
  /// writes it, outside the fake async zone like Flutter; a failure is the
  /// message in both modes. Disposes the image only when [isOwned] (a
  /// capture), never one the caller passed.
  static Future<String?> _matchImage(
    Future<ui.Image?> pending,
    _Golden golden, {
    List<PixelRegion> textRegions = const [],
    bool isOwned = false,
  }) => flutter_test.TestWidgetsFlutterBinding.instance.runAsync<String?>(
    () => _matchLoaded(
      pending,
      golden,
      textRegions: textRegions,
      isOwned: isOwned,
    ),
  );

  /// [_matchImage] once outside the fake async zone.
  static Future<String?> _matchLoaded(
    Future<ui.Image?> pending,
    _Golden golden, {
    required List<PixelRegion> textRegions,
    required bool isOwned,
  }) async {
    final image = await pending;
    if (image == null) {
      throw AssertionError('Future<Image> completed to null');
    }
    try {
      return golden.isUpdate
          ? await _update(image, golden)
          : await _compare(image, golden, textRegions);
    } on flutter_test.TestFailure catch (error) {
      return error.message;
    } finally {
      if (isOwned) image.dispose();
    }
  }

  /// Writes [image] as [golden].
  static Future<String?> _update(ui.Image image, _Golden golden) async {
    final png = await image.toByteData(format: .png);
    // Flutter's own message.
    if (png == null) return 'could not encode screenshot.';
    await golden.comparator.update(golden.uri, Uint8List.sublistView(png));

    return null;
  }

  /// Compares [image] as raw pixels with [golden].
  static Future<String?> _compare(
    ui.Image image,
    _Golden golden,
    List<PixelRegion> textRegions,
  ) async {
    final pixels = await image.toByteData(format: .rawStraightRgba);
    if (pixels == null) return 'could not read the pixels of the screenshot.';
    golden.comparator.compareRaw(
      golden.uri,
      Uint8List.sublistView(pixels),
      width: image.width,
      height: image.height,
      textRegions: textRegions,
    );

    return null;
  }
}

/// Where a match goes: the golden and its comparator, and whether it is
/// written (`--update-goldens`) rather than compared.
typedef _Golden = ({GleonGoldenComparator comparator, bool isUpdate, Uri uri});
