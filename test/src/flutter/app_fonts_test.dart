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

  test('Roboto comes from the Flutter SDK of FLUTTER_ROOT', () {
    final faces = AppFonts.sdkRoboto(Platform.environment);

    expect(
      faces.map((face) => face.uri.pathSegments.lastOrNull),
      AppFonts.robotoFaces,
    );
    expect(faces.every((face) => face.existsSync()), isTrue);
  });

  // `flutter test` sets FLUTTER_ROOT; another runner may not, and an SDK may
  // lack a face.
  test('an SDK without Roboto says what to do', () {
    final sdk = Directory.systemTemp.createTempSync('gleon_sdk_');
    addTearDown(() => sdk.deleteSync(recursive: true));
    File('${sdk.path}/${AppFonts.sdkFonts}/Roboto-Regular.ttf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [0]);

    for (final (environment, root) in [
      (const <String, String>{}, 'not set'),
      ({'FLUTTER_ROOT': sdk.path}, sdk.path),
    ]) {
      expect(
        () => AppFonts.sdkRoboto(environment),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('found no Roboto in the Flutter SDK'),
              contains('FLUTTER_ROOT is $root'),
              contains('flutter test'),
              contains('bundle Roboto'),
            ),
          ),
        ),
        reason: root,
      );
    }
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

  return .syncValue(switch (key) {
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
