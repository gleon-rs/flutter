import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gleon/gleon.dart';

import '../helpers/png.dart';

// The text-regions plan hands the engine the captured frame as raw straight
// RGBA instead of encoding a PNG on every run. That only works if both read
// the same pixels: checked on every OS of CI, translucent pixels included
// (where premultiplied and straight alpha differ).
void main() {
  testWidgets('raw straight RGBA is the PNG of the same frame', (tester) async {
    await tester.pumpWidget(const _Translucent());
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_Translucent.boundaryKey),
    );

    final frame = await tester.runAsync(() => _capture(boundary));
    if (frame == null) fail('the capture did not finish');
    final (:raw, :png) = frame;
    final decoded = decodeRgbaPng(png);
    final alphas = Iterable<int>.generate(
      raw.length ~/ 4,
      (pixel) => ByteData.sublistView(raw).getUint8(pixel * 4 + 3),
    );

    expect((decoded.width, decoded.height), (96, 64));
    expect(
      alphas,
      contains(inExclusiveRange(0, 255)),
      reason: 'the frame has translucent pixels',
    );
    expect(raw, decoded.rgba);
  });
}

/// The frame of [boundary] as raw straight RGBA and as PNG.
Future<({Uint8List png, Uint8List raw})> _capture(
  RenderRepaintBoundary boundary,
) async {
  final image = await boundary.toImage();
  try {
    final raw = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (raw == null || png == null) throw StateError('no frame bytes');

    return (png: Uint8List.sublistView(png), raw: Uint8List.sublistView(raw));
  } finally {
    image.dispose();
  }
}

/// Translucent fills, a fading gradient, group opacity and an anti-aliased
/// circle over a transparent background.
class _Translucent extends StatelessWidget {
  const _Translucent();

  static const boundaryKey = ValueKey<String>('translucent');

  @override
  Widget build(BuildContext context) => const Align(
    alignment: .topLeft,
    child: RepaintBoundary(
      key: boundaryKey,
      child: SizedBox(
        width: 96,
        height: 64,
        child: CustomPaint(painter: _TranslucentPainter()),
      ),
    ),
  );
}

class _TranslucentPainter extends CustomPainter {
  const _TranslucentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gradient = const LinearGradient(
      colors: [Color(0x00FFFFFF), Color(0xC0000000)],
    ).createShader(Offset.zero & size);
    canvas
      ..drawRect(
        const Rect.fromLTWH(4, 4, 40, 24),
        Paint()..color = const Color(0x80E91E63),
      )
      ..drawRect(
        Rect.fromLTWH(0, 36, size.width, 20),
        Paint()..shader = gradient,
      )
      ..saveLayer(null, Paint()..color = const Color(0x59000000))
      ..drawRect(
        const Rect.fromLTWH(24, 12, 40, 30),
        Paint()..color = const Color(0xFF2196F3),
      )
      ..restore()
      ..drawCircle(
        const Offset(76.3, 20.7),
        13.4,
        Paint()..color = const Color(0xB34CAF50),
      );
  }

  @override
  bool shouldRepaint(_TranslucentPainter oldDelegate) => false;
}
