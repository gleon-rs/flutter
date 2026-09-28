import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Anti-aliased content (a circle and thin strokes) drawn at a sub-pixel
/// [offset], emulating rasterization noise between machines.
class Blob extends StatelessWidget {
  /// Creates the blob, shifted by [offset] pixels on both axes.
  const Blob({this.offset = 0, super.key});

  /// Key of the captured boundary.
  static const boundaryKey = ValueKey<String>('blob');

  /// Its golden, relative to the test files.
  static const golden = 'goldens/blob.png';

  /// Finds the captured boundary.
  static Finder get finder => find.byKey(boundaryKey);

  /// Sub-pixel shift of all content.
  final double offset;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('offset', offset));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: .ltr,
    child: Align(
      alignment: .topLeft,
      child: RepaintBoundary(
        key: boundaryKey,
        child: CustomPaint(
          painter: _BlobPainter(offset),
          size: const Size(120, 80),
        ),
      ),
    ),
  );
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter(this.offset);

  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF))
      ..drawCircle(
        Offset(offset + 30, offset + 40),
        18.5,
        Paint()..color = const Color(0xFF9C27B0),
      );
    final stroke = Paint()
      ..color = const Color(0xFF212121)
      ..strokeWidth = 1.4;
    for (int i = 0; i < 8; i += 1) {
      final x = offset + i * 6.1 + 62.3;
      canvas.drawLine(Offset(x, offset + 28), Offset(x, offset + 52), stroke);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter oldDelegate) => oldDelegate.offset != offset;
}
