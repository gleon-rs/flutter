import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/flutter/app_fonts.dart';

// The text-regions plan loads real fonts in tests (Roboto from the Flutter
// SDK) and only tolerates differences inside the boxes of text. That only
// works if every OS lays the text out alike, so the boxes and everything around
// them stay in place: the line metrics are pinned to the values measured on
// macOS and checked on every OS of CI. Windows takes line metrics from other
// font tables, which `loadAppFonts` aligns the fonts for.
void main() {
  test('the Flutter SDK provides Roboto to tests', () {
    for (final file in _files) {
      expect(File(_path(file)).existsSync(), isTrue, reason: file);
    }
  });

  test('Windows line metrics are aligned with hhea, checksums kept', () {
    final font = AppFonts.withPortableLineMetrics(
      File(_path('Roboto-Regular.ttf')).readAsBytesSync(),
    );
    final data = ByteData.sublistView(font);
    final tables = _tables(font);
    final (hhea, os2) = (tables['hhea'] ?? -1, tables['OS/2'] ?? -1);

    expect(
      (data.getUint16(os2 + 74), data.getUint16(os2 + 76)),
      (data.getInt16(hhea + 4), -data.getInt16(hhea + 6)),
    );
    expect((data.getUint16(os2 + 74), data.getUint16(os2 + 76)), (1900, 500));
    expect(
      [
        for (final field in [68, 70, 72]) data.getInt16(os2 + field),
      ],
      [
        for (final field in [4, 6, 8]) data.getInt16(hhea + field),
      ],
      reason: 'sTypo* are hhea',
    );
    expect(AppFonts.checksum(data, 0, font.length), 0xB1B0AFBA);
  });

  test('checksums pad the last word with zeros', () {
    final data = ByteData.sublistView(Uint8List.fromList([1, 2, 3, 4, 5]));

    expect(AppFonts.checksum(data, 0, 5), 0x01020304 + 0x05000000);
    expect(AppFonts.checksum(data, 1, 3), 0x02030400);
  });

  test('a font with a truncated hhea table is kept as it is', () {
    final font = File(_path('Roboto-Regular.ttf')).readAsBytesSync();
    // The record's length: the line gap at bytes 8..10 would be beyond it.
    ByteData.sublistView(font).setUint32(_record(font, 'hhea') + 12, 8);

    expect(AppFonts.withPortableLineMetrics(font), font);
  });

  testWidgets('Roboto lays text out alike on every OS', (tester) async {
    await tester.runAsync(loadAppFonts);
    final lines = [
      for (final size in [10.0, 12.0, 14.0, 16.0, 24.0])
        for (final weight in const [
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w700,
        ])
          ..._lines(size, weight),
    ];

    expect(lines, _onMacOS);
  });

  // Roboto has no USE_TYPO_METRICS; many app fonts do, and some systems then
  // measure lines by `OS/2` `sTypo*` (for Roboto 1536/-512 + 102, not hhea).
  testWidgets('a font with USE_TYPO_METRICS lays text out alike too', (
    tester,
  ) async {
    await tester.runAsync(() => _loadVariant(_typoRoboto, _setUseTypoMetrics));
    final lines = [
      for (final size in [10.0, 12.0, 14.0, 16.0, 24.0])
        for (final weight in const [
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w700,
        ])
          ..._lines(size, weight, family: _typoRoboto),
    ];

    expect(lines, _onMacOS);
  });

  // Roboto's line gap is 0; other fonts have one, which every system must add
  // the same way (DirectWrite derives it from hhea and the Windows metrics).
  testWidgets('a font with a line gap lays text out alike too', (tester) async {
    await tester.runAsync(() => _loadVariant(_gapRoboto, _setLineGap));

    expect(_lines(14, .w400, family: _gapRoboto), _withLineGapOnMacOS);
  });
}

/// Roboto with USE_TYPO_METRICS set, as an app font would have it.
const _typoRoboto = 'RobotoTypo';

/// Roboto with a line gap.
const _gapRoboto = 'RobotoGap';

/// Loads [_files] as [family], each changed by [change] and made portable.
Future<void> _loadVariant(String family, void Function(Uint8List font) change) {
  final loader = FontLoader(family);
  for (final file in _files) {
    final font = File(_path(file)).readAsBytesSync();
    change(font);
    final portable = AppFonts.withPortableLineMetrics(font);
    loader.addFont(.value(ByteData.sublistView(portable)));
  }

  return loader.load();
}

void _setUseTypoMetrics(Uint8List font) {
  final fsSelection = _os2(font) + 62;
  final data = ByteData.sublistView(font);
  data.setUint16(fsSelection, data.getUint16(fsSelection) | _useTypoMetrics);
}

/// Sets the `hhea` line gap to 200 units (of 2048) and its table checksum.
void _setLineGap(Uint8List font) {
  final record = _record(font, 'hhea');
  final data = ByteData.sublistView(font);
  final (offset, length) = (
    data.getUint32(record + 8),
    data.getUint32(record + 12),
  );
  data
    ..setInt16(offset + 8, 200)
    ..setUint32(record + 4, AppFonts.checksum(data, offset, length));
}

/// The offset of the table record of [tag] in [font].
int _record(Uint8List font, String tag) {
  final data = ByteData.sublistView(font);
  for (int index = 0; index < data.getUint16(4); index += 1) {
    final record = index * 16 + 12;
    if (String.fromCharCodes(font, record, record + 4) == tag) return record;
  }

  return fail('no $tag table');
}

/// Measured on macOS (arm64), Flutter 3.47.6.
const _withLineGapOnMacOS = [
  '14.0 400 0: 0.0 13.8984375 172.251953125 18.0 13.671875 4.1015625',
  '14.0 400 1: 0.0 31.8984375 169.50390625 18.0 13.671875 4.1015625',
  '14.0 400 2: 0.0 49.8984375 108.8212890625 18.0 13.671875 4.1015625',
];

/// The offset of the `OS/2` table of [font].
int _os2(Uint8List font) => _tables(font)['OS/2'] ?? fail('no OS/2 table');

/// The USE_TYPO_METRICS bit of `OS/2` `fsSelection`.
const _useTypoMetrics = 0x80;

const _files = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];

const _sample =
    'Submit the quick brown fox, 0123456789; Cancel jumps over the lazy dog.';

String _path(String file) {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      fail('`flutter test` sets FLUTTER_ROOT');

  return '$root/${AppFonts.sdkFonts}/$file';
}

/// The offsets of the tables of [font] by tag.
Map<String, int> _tables(Uint8List font) {
  final data = ByteData.sublistView(font);

  return {
    for (int index = 0; index < data.getUint16(4); index += 1)
      String.fromCharCodes(font, index * 16 + 12, index * 16 + 16): data
          .getUint32(index * 16 + 20),
  };
}

/// Every line of [_sample] wrapped at 180 px in [family] (Roboto) of [size]
/// and [weight], as `size weight line: left baseline width height ascent
/// descent`.
List<String> _lines(
  double size,
  FontWeight weight, {
  String family = 'Roboto',
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: _sample,
      style: TextStyle(fontSize: size, fontWeight: weight, fontFamily: family),
    ),
    textDirection: .ltr,
  )..layout(maxWidth: 180);
  try {
    return [
      for (final LineMetrics(
            :ascent,
            :baseline,
            :descent,
            :height,
            :left,
            :lineNumber,
            :width,
          )
          in painter.computeLineMetrics())
        [
          size,
          weight.value,
          '$lineNumber:',
          left,
          baseline,
          width,
          height,
          ascent,
          descent,
        ].join(' '),
    ];
  } finally {
    painter.dispose();
  }
}

/// Measured on macOS (arm64), Flutter 3.47.5.
const _onMacOS = [
  '10.0 400 0: 0.0 9.55859375 123.037109375 12.0 9.27734375 2.44140625',
  '10.0 400 1: 0.0 21.55859375 179.21875 12.0 9.27734375 2.44140625',
  '10.0 400 2: 0.0 33.55859375 19.5849609375 12.0 9.27734375 2.44140625',
  '10.0 500 0: 0.0 9.55859375 124.267578125 12.0 9.27734375 2.44140625',
  '10.0 500 1: 0.0 21.55859375 161.0107421875 12.0 9.27734375 2.44140625',
  '10.0 500 2: 0.0 33.55859375 40.1513671875 12.0 9.27734375 2.44140625',
  '10.0 700 0: 0.0 9.55859375 125.224609375 12.0 9.27734375 2.44140625',
  '10.0 700 1: 0.0 21.55859375 162.3583984375 12.0 9.27734375 2.44140625',
  '10.0 700 2: 0.0 33.55859375 40.5126953125 12.0 9.27734375 2.44140625',
  '12.0 400 0: 0.0 11.0703125 147.64453125 14.0 11.1328125 2.9296875',
  '12.0 400 1: 0.0 25.0703125 171.169921875 14.0 11.1328125 2.9296875',
  '12.0 400 2: 0.0 39.0703125 67.39453125 14.0 11.1328125 2.9296875',
  '12.0 500 0: 0.0 11.0703125 149.12109375 14.0 11.1328125 2.9296875',
  '12.0 500 1: 0.0 25.0703125 173.1328125 14.0 11.1328125 2.9296875',
  '12.0 500 2: 0.0 39.0703125 68.26171875 14.0 11.1328125 2.9296875',
  '12.0 700 0: 0.0 11.0703125 150.26953125 14.0 11.1328125 2.9296875',
  '12.0 700 1: 0.0 25.0703125 174.5859375 14.0 11.1328125 2.9296875',
  '12.0 700 2: 0.0 39.0703125 68.859375 14.0 11.1328125 2.9296875',
  '14.0 400 0: 0.0 12.58203125 172.251953125 16.0 12.98828125 3.41796875',
  '14.0 400 1: 0.0 28.58203125 169.50390625 16.0 12.98828125 3.41796875',
  '14.0 400 2: 0.0 44.58203125 108.8212890625 16.0 12.98828125 3.41796875',
  '14.0 500 0: 0.0 12.58203125 173.974609375 16.0 12.98828125 3.41796875',
  '14.0 500 1: 0.0 28.58203125 171.36328125 16.0 12.98828125 3.41796875',
  '14.0 500 2: 0.0 44.58203125 110.263671875 16.0 12.98828125 3.41796875',
  '14.0 700 0: 0.0 12.58203125 175.314453125 16.0 12.98828125 3.41796875',
  '14.0 700 1: 0.0 28.58203125 172.7236328125 16.0 12.98828125 3.41796875',
  '14.0 700 2: 0.0 44.58203125 111.2958984375 16.0 12.98828125 3.41796875',
  '16.0 400 0: 0.0 15.09375 167.3125 19.0 14.84375 3.90625',
  '16.0 400 1: 0.0 34.09375 175.4140625 19.0 14.84375 3.90625',
  '16.0 400 2: 0.0 53.09375 172.21875 19.0 14.84375 3.90625',
  '16.0 500 0: 0.0 15.09375 168.6640625 19.0 14.84375 3.90625',
  '16.0 500 1: 0.0 34.09375 177.9375 19.0 14.84375 3.90625',
  '16.0 500 2: 0.0 53.09375 174.0859375 19.0 14.84375 3.90625',
  '16.0 700 0: 0.0 15.09375 169.7109375 19.0 14.84375 3.90625',
  '16.0 700 1: 0.0 34.09375 179.8671875 19.0 14.84375 3.90625',
  '16.0 700 2: 0.0 53.09375 175.375 19.0 14.84375 3.90625',
  '24.0 400 0: 0.0 22.140625 178.7109375 28.0 22.265625 5.859375',
  '24.0 400 1: 0.0 50.140625 110.63671875 28.0 22.265625 5.859375',
  '24.0 400 2: 0.0 78.140625 139.83984375 28.0 22.265625 5.859375',
  '24.0 400 3: 0.0 106.140625 144.796875 28.0 22.265625 5.859375',
  '24.0 400 4: 0.0 134.140625 133.60546875 28.0 22.265625 5.859375',
  '24.0 400 5: 0.0 162.140625 47.00390625 28.0 22.265625 5.859375',
  '24.0 500 0: 0.0 22.140625 116.484375 28.0 22.265625 5.859375',
  '24.0 500 1: 0.0 50.140625 175.78125 28.0 22.265625 5.859375',
  '24.0 500 2: 0.0 78.140625 142.11328125 28.0 22.265625 5.859375',
  '24.0 500 3: 0.0 106.140625 145.67578125 28.0 22.265625 5.859375',
  '24.0 500 4: 0.0 134.140625 135.52734375 28.0 22.265625 5.859375',
  '24.0 500 5: 0.0 162.140625 47.51953125 28.0 22.265625 5.859375',
  '24.0 700 0: 0.0 22.140625 117.43359375 28.0 22.265625 5.859375',
  '24.0 700 1: 0.0 50.140625 177.12890625 28.0 22.265625 5.859375',
  '24.0 700 2: 0.0 78.140625 143.98828125 28.0 22.265625 5.859375',
  '24.0 700 3: 0.0 106.140625 146.1328125 28.0 22.265625 5.859375',
  '24.0 700 4: 0.0 134.140625 137.05078125 28.0 22.265625 5.859375',
  '24.0 700 5: 0.0 162.140625 47.765625 28.0 22.265625 5.859375',
];
