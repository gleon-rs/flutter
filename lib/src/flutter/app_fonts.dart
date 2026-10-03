import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real fonts of the app into this test process, so goldens show
/// text instead of the boxes of Flutter's test font: every family of the
/// app's `FontManifest.json` (its own fonts, those of its packages,
/// `MaterialIcons`) under its exact name, and `Roboto` (Material's default)
/// from the Flutter SDK unless the app bundles it.
///
/// The fonts are aligned to lay text out alike on every OS: Windows takes
/// line heights from other font tables than macOS and Linux, which
/// [AppFonts.withPortableLineMetrics] makes agree. Goldens therefore differ
/// only in the rasterization of glyphs, inside the boxes of text.
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
/// Later calls reuse the first. Throws a [StateError] when the Flutter SDK
/// has no Roboto (`flutter test` sets `FLUTTER_ROOT`).
// ignore: prefer-static-class, the setup call of test configs.
Future<void> loadAppFonts() => AppFonts._loaded ??= AppFonts._load();

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

  static Future<void>? _loaded;

  static Future<void> _load() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final families = <String, List<String>>{};
    final manifest = json.decode(
      await rootBundle.loadString('FontManifest.json'),
    );
    if (manifest is List<Object?>) {
      for (final family in manifest) {
        if (family case {
          'family': final String name,
          'fonts': final List<Object?> fonts,
        }) {
          families[name] = [
            for (final font in fonts)
              if (font case {'asset': final String asset}) asset,
          ];
        }
      }
    }
    for (final MapEntry(key: family, value: keys) in families.entries) {
      await _loadFamily(family, [
        for (final key in keys) await rootBundle.load(key),
      ]);
    }
    if (!families.containsKey('Roboto')) {
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

  /// A copy of the TrueType/OpenType [font] whose Windows and typographic
  /// line metrics are its `hhea` ones, so text lays out alike on every OS.
  ///
  /// macOS (CoreText) and Linux (FreeType) take a font's ascent and descent
  /// from `hhea`, Windows (DirectWrite) from `OS/2`
  /// `usWinAscent`/`usWinDescent`; Roboto has 1900/500 there and 1946/512
  /// here (of 2048 units), so on Windows every line is taller and every
  /// baseline lower. Fonts whose `fsSelection` has USE_TYPO_METRICS (many
  /// newer ones) are measured by `OS/2` `sTypo*` instead on some systems, so
  /// those are aligned too. The `OS/2` table checksum and the font's
  /// `checkSumAdjustment` are recomputed. A font collection, or a font
  /// without these tables, is returned unchanged.
  static Uint8List withPortableLineMetrics(Uint8List font) {
    final copy = Uint8List.fromList(font);
    final data = ByteData.sublistView(copy);
    if (copy.length < 12 || String.fromCharCodes(copy, 0, 4) == 'ttcf') {
      return copy;
    }
    final tables = <String, ({int length, int offset, int record})>{};
    for (int index = 0; index < data.getUint16(4); index += 1) {
      final record = index * 16 + 12;
      if (record + 16 > copy.length) return copy;
      tables[String.fromCharCodes(copy, record, record + 4)] = (
        length: data.getUint32(record + 12),
        offset: data.getUint32(record + 8),
        record: record,
      );
    }
    final (hhea, os2, head) = (tables['hhea'], tables['OS/2'], tables['head']);
    if (hhea == null ||
        os2 == null ||
        head == null ||
        hhea.length < 10 ||
        hhea.offset + hhea.length > copy.length ||
        head.offset + 12 > copy.length ||
        os2.length < 78 ||
        os2.offset + os2.length > copy.length) {
      return copy;
    }

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
      // The whole-font checksum is taken with the adjustment itself zeroed.
      ..setUint32(head.offset + 8, 0)
      ..setUint32(
        head.offset + 8,
        (0xB1B0AFBA - checksum(data, 0, copy.length)) & 0xFFFFFFFF,
      );

    return copy;
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
