import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:gleon/gleon.dart';

// The text-regions plan loads real fonts in tests (Roboto from the Flutter
// SDK) and only tolerates differences inside the boxes of text. That only
// works if every OS lays the text out alike, so the boxes and everything around
// them stay in place: the line metrics are pinned to the values measured on
// macOS and checked on every OS of CI.
void main() {
  test('the Flutter SDK provides Roboto to tests', () {
    for (final file in _files) {
      expect(File(_path(file)).existsSync(), isTrue, reason: file);
    }
  });

  testWidgets('Roboto lays text out alike on every OS', (tester) async {
    await tester.runAsync(_load);
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
}

const _files = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];

const _sample =
    'Submit the quick brown fox, 0123456789; Cancel jumps over the lazy dog.';

String _path(String file) {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      fail('`flutter test` sets FLUTTER_ROOT');

  return '$root/bin/cache/artifacts/material_fonts/$file';
}

Future<void> _load() async {
  final loader = FontLoader('Roboto');
  for (final file in _files) {
    final bytes = File(_path(file)).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Every line of [_sample] wrapped at 180 px in Roboto of [size] and [weight],
/// as `size weight line: left baseline width height ascent descent`.
List<String> _lines(double size, FontWeight weight) {
  final painter = TextPainter(
    text: TextSpan(
      text: _sample,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        fontFamily: 'Roboto',
      ),
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
