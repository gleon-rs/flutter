import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shared_load.dart';

/// Loads the real fonts of the app into this test process, so goldens show
/// text instead of the boxes of Flutter's test font: every family of the
/// app's `FontManifest.json` (its own fonts, those of its packages,
/// `MaterialIcons`) under its exact name, and `Roboto` (Material's default)
/// from the Flutter SDK unless the app bundles it.
///
/// The fonts are aligned to lay text out alike on every OS: Windows takes
/// line heights from other font tables than macOS and Linux, so the Windows
/// and typographic line metrics of every font are set to its `hhea` ones
/// (TrueType collections, `.ttc`, are loaded as they are). Goldens therefore
/// differ only in the rasterization of glyphs, inside the boxes of text.
/// Line heights on Windows can differ from the real app there.
///
/// Call it once, before the tests, from `test/flutter_test_config.dart`:
///
/// ```dart
/// import "dart:async";
///
/// import "package:gleon/gleon.dart";
///
/// Future<void> testExecutable(FutureOr<void> Function() testMain) async {
///   await loadAppFonts();
///   await testMain();
/// }
/// ```
///
/// or from `setUpAll`. Inside a test body time is fake and the file reads
/// never complete: there, call `await tester.runAsync(loadAppFonts)`.
///
/// Later calls reuse the first; a load that failed, or that a test left
/// unfinished (awaited in its body without `runAsync`), is started again.
/// Throws a [StateError] when the Flutter SDK has no Roboto (`flutter test`
/// sets `FLUTTER_ROOT`).
// ignore: prefer-static-class, the setup call of test configs.
Future<void> loadAppFonts() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final loading = AppFonts._fonts.load();
  // A load awaited in a test body never finishes under its fake time: the
  // next test starts its own instead of waiting for this one forever.
  if (binding.inTest) addTearDown(AppFonts._fonts.forgetUnfinished);

  return loading;
}

/// The fonts of [loadAppFonts].
abstract final class AppFonts {
  /// Where the Flutter SDK keeps Material's fonts, relative to its root.
  static const sdkFonts = 'bin/cache/artifacts/material_fonts';

  /// Roboto's faces in [sdkFonts].
  static const robotoFaces = [
    'Roboto-Thin.ttf',
    'Roboto-ThinItalic.ttf',
    'Roboto-Light.ttf',
    'Roboto-LightItalic.ttf',
    'Roboto-Regular.ttf',
    'Roboto-Italic.ttf',
    'Roboto-Medium.ttf',
    'Roboto-MediumItalic.ttf',
    'Roboto-Bold.ttf',
    'Roboto-BoldItalic.ttf',
    'Roboto-Black.ttf',
    'Roboto-BlackItalic.ttf',
  ];

  /// The fonts, loaded once for every caller.
  // ignore: prefer-correct-handler-name, the loader of the fonts, no handler.
  static final _fonts = SharedLoad(_load);

  static Future<void> _load() async {
    // `load`, not `loadString`: the bundle caches the future of the latter,
    // and one a test left unfinished would never complete for a later load.
    final manifest = json.decode(
      utf8.decode(
        Uint8List.sublistView(await rootBundle.load('FontManifest.json')),
      ),
    );
    bool hasRoboto = false;
    if (manifest is List<Object?>) {
      for (final family in manifest) {
        if (family case {
          'family': final String name,
          'fonts': final List<Object?> fonts,
        }) {
          // One file per face: a variable font listed under several weights
          // is loaded (and aligned) once.
          final files = {
            for (final font in fonts)
              if (font case {'asset': final String asset}) asset,
          };
          // One after another: loaded all at once, the text of the example's
          // goldens rendered differently (measured on 2026-10-21; the order
          // in which faces are registered matters).
          await _loadFamily(name, [
            for (final file in files) await rootBundle.load(file),
          ]);
          hasRoboto |= name == 'Roboto';
        }
      }
    }
    if (!hasRoboto) {
      await _loadFamily('Roboto', [
        for (final file in _sdkRoboto)
          ByteData.sublistView(await file.readAsBytes()),
      ]);
    }
  }

  static Future<void> _loadFamily(String family, List<ByteData> fonts) async {
    final loader = FontLoader(family);
    for (final font in fonts) {
      final portable = withPortableLineMetrics(Uint8List.sublistView(font));
      loader.addFont(.value(ByteData.sublistView(portable)));
    }
    await loader.load();
  }

  /// The [robotoFaces] of the Flutter SDK.
  static List<File> get _sdkRoboto {
    final root = Platform.environment['FLUTTER_ROOT'];
    final faces = root == null
        ? const <File>[]
        : [for (final face in robotoFaces) File('$root/$sdkFonts/$face')];
    if (faces.isEmpty || !faces.every((face) => face.existsSync())) {
      throw StateError(
        'gleon: loadAppFonts found no Roboto in the Flutter SDK '
        '(FLUTTER_ROOT/$sdkFonts, FLUTTER_ROOT is ${root ?? 'not set'}). Run '
        'the tests with `flutter test`, or bundle Roboto as a font of the '
        'app.',
      );
    }

    return faces;
  }

  /// The TrueType/OpenType [font] with its Windows and typographic line
  /// metrics set to its `hhea` ones (in a copy), so text lays out alike on
  /// every OS.
  ///
  /// macOS (CoreText) and Linux (FreeType) take a font's ascent and descent
  /// from `hhea`, Windows (DirectWrite) from `OS/2`
  /// `usWinAscent`/`usWinDescent`; Roboto has 1900/500 there and 1946/512
  /// here (of 2048 units), so on Windows every line is taller and every
  /// baseline lower. Fonts whose `fsSelection` has USE_TYPO_METRICS (many
  /// newer ones) are measured by `OS/2` `sTypo*` instead on some systems, so
  /// those are aligned too. The `OS/2` table checksum is recomputed and the
  /// font's `checkSumAdjustment` updated by the change, without reading the
  /// rest of the font (a font whose checksum held keeps it; renderers do not
  /// check it). A font collection, or a font without these tables, is
  /// returned as it is (not copied).
  static Uint8List withPortableLineMetrics(Uint8List font) {
    final tables = _metricTables(font);
    if (tables == null) return font;
    final (:head, :hhea, :os2) = tables;
    final copy = Uint8List.fromList(font);
    final data = ByteData.sublistView(copy);
    // The words this changes: the five line metrics of `OS/2`, its table
    // checksum and `checkSumAdjustment` (whole-font checksums add words).
    final changed = [
      (start: os2.offset + 68, end: os2.offset + 78),
      (start: os2.record + 4, end: os2.record + 8),
      (start: head.offset + 8, end: head.offset + 12),
    ];
    final wordsBefore = _sumOfWords(data, changed);
    final above = data.getInt16(hhea.offset + 4);
    final below = data.getInt16(hhea.offset + 6);
    data
      // The typographic ascender, descender and line gap are used instead
      // where `fsSelection` has USE_TYPO_METRICS.
      ..setInt16(os2.offset + 68, above)
      ..setInt16(os2.offset + 70, below)
      ..setInt16(os2.offset + 72, data.getInt16(hhea.offset + 8))
      ..setUint16(os2.offset + 74, above.clamp(0, 0xFFFF))
      ..setUint16(os2.offset + 76, (-below).clamp(0, 0xFFFF))
      ..setUint32(os2.record + 4, checksum(data, os2.offset, os2.length))
      ..setUint32(head.offset + 8, 0)
      // The whole-font checksum (the adjustment counted as zero) was
      // 0xB1B0AFBA minus the adjustment and changed by the changed words: the
      // new adjustment makes it 0xB1B0AFBA again.
      ..setUint32(
        head.offset + 8,
        (wordsBefore - _sumOfWords(data, changed)) & 0xFFFFFFFF,
      );

    return copy;
  }

  /// The `head`, `hhea` and `OS/2` table records of [font], or null for a
  /// font collection, a font without them, or one too short for them.
  static _MetricTables? _metricTables(Uint8List font) {
    if (font.length < 12 || String.fromCharCodes(font, 0, 4) == 'ttcf') {
      return null;
    }
    final data = ByteData.sublistView(font);
    final tables = <String, _Table>{};
    for (int index = 0; index < data.getUint16(4); index += 1) {
      final record = index * 16 + 12;
      if (record + 16 > font.length) return null;
      tables[String.fromCharCodes(font, record, record + 4)] = (
        length: data.getUint32(record + 12),
        offset: data.getUint32(record + 8),
        record: record,
      );
    }
    final (hhea, os2, head) = (tables['hhea'], tables['OS/2'], tables['head']);

    return hhea == null ||
            os2 == null ||
            head == null ||
            head.length < 12 ||
            hhea.length < 10 ||
            hhea.offset + hhea.length > font.length ||
            head.offset + 12 > font.length ||
            os2.length < 78 ||
            os2.offset + os2.length > font.length
        ? null
        : (head: head, hhea: hhea, os2: os2);
  }

  /// The checksum of the whole words of the font (aligned to its start)
  /// that hold the bytes of [ranges].
  static int _sumOfWords(ByteData data, List<_Range> ranges) {
    int sum = 0;
    for (final (:end, :start) in ranges) {
      final first = start - start % 4;
      final last = (end + 3) ~/ 4 * 4;
      final until = last < data.lengthInBytes ? last : data.lengthInBytes;
      sum = (sum + checksum(data, first, until - first)) & 0xFFFFFFFF;
    }

    return sum;
  }

  /// The OpenType checksum of [length] bytes at [offset]: the sum of
  /// big-endian 32-bit words, the last one padded with zeros.
  static int checksum(ByteData data, int offset, int length) {
    final end = offset + length;
    final whole = offset + length - length % 4;
    int sum = 0;
    for (int word = offset; word < whole; word += 4) {
      sum = (sum + data.getUint32(word)) & 0xFFFFFFFF;
    }
    if (whole < end) {
      int last = 0;
      for (int byte = whole; byte < whole + 4; byte += 1) {
        last = (last << 8) | (byte < end ? data.getUint8(byte) : 0);
      }
      sum = (sum + last) & 0xFFFFFFFF;
    }

    return sum;
  }
}

/// A table record of a font: where its table lies, and where the record is.
typedef _Table = ({int length, int offset, int record});

/// The tables [AppFonts.withPortableLineMetrics] reads or changes.
typedef _MetricTables = ({_Table head, _Table hhea, _Table os2});

/// The bytes from `start` to `end` of a font.
typedef _Range = ({int end, int start});
