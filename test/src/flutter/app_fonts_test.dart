import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/flutter/app_fonts.dart';

// `loadAppFonts` loads the families of the app's `FontManifest.json` under
// their exact names, including those of its packages. The manifest of this
// package has none of its own, so the asset channel serves one here: a font of
// a `brand` package (Roboto Condensed from the Flutter SDK).
void main() {
  setUpAll(_loadBrandFonts);

  testWidgets('loads the font families of the app and its packages', (
    tester,
  ) async {
    final brand = _width(_brandFamily);
    final roboto = _width('Roboto');

    // Flutter's test font draws every glyph as a square of the font size.
    expect(_width('FlutterTest'), _sample.length * _fontSize);
    expect(brand, isNot(_width('FlutterTest')));
    expect(brand, lessThan(roboto), reason: 'condensed');
  });
}

Future<void> _loadBrandFonts() {
  TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', _assets);

  return loadAppFonts();
}

const _brandFamily = 'packages/brand/Condensed';
const _brandAsset = 'packages/brand/fonts/Condensed.ttf';
const _sample = 'Submit';
const _fontSize = 20.0;

/// The `flutter/assets` channel: the manifest and the brand font.
Future<ByteData?> _assets(ByteData? message) {
  final key = message == null
      ? null
      : utf8.decode(Uint8List.sublistView(message));

  return .value(switch (key) {
    'FontManifest.json' => ByteData.sublistView(
      utf8.encode(
        json.encode([
          {
            'family': _brandFamily,
            'fonts': [
              {'asset': _brandAsset},
            ],
          },
        ]),
      ),
    ),
    _brandAsset => ByteData.sublistView(
      File(
        '${Platform.environment['FLUTTER_ROOT'] ?? fail('no FLUTTER_ROOT')}/'
        '${AppFonts.sdkFonts}/RobotoCondensed-Regular.ttf',
      ).readAsBytesSync(),
    ),
    _ => null,
  });
}

/// The width of [_sample] in [family].
double _width(String family) {
  final painter = TextPainter(
    text: TextSpan(
      text: _sample,
      style: TextStyle(fontSize: _fontSize, fontFamily: family),
    ),
    textDirection: .ltr,
  )..layout();
  try {
    return painter.width;
  } finally {
    painter.dispose();
  }
}
