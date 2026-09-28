import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic, text-free widget: solid rectangles on integer coordinates
/// render identically regardless of font rasterization.
class Swatch extends StatelessWidget {
  /// Creates the swatch; [dot] adds one black pixel, [accent] recolors the
  /// left half.
  const Swatch({
    this.size = const Size(100, 60),
    this.dot,
    this.accent = const Color(0xFF2196F3),
    super.key,
  });

  /// Key of the captured boundary.
  static const boundaryKey = ValueKey<String>('swatch');

  /// Its golden, relative to the test files.
  static const golden = 'goldens/swatch.png';

  /// Where tests put a single changed pixel.
  static const dotOffset = Offset(10, 10);

  /// Finds the captured boundary.
  static Finder get finder => find.byKey(boundaryKey);

  /// Canvas size (the golden is 100x60).
  final Size size;

  /// Position of an extra 1x1 black pixel, if any.
  final Offset? dot;

  /// Color of the left half.
  final Color accent;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Size>('size', size))
      ..add(DiagnosticsProperty<Offset>('dot', dot, defaultValue: null))
      ..add(ColorProperty('accent', accent));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: .ltr,
    child: Align(
      alignment: .topLeft,
      child: RepaintBoundary(
        key: boundaryKey,
        child: CustomPaint(
          painter: _SwatchPainter(dot: dot, accent: accent),
          size: size,
        ),
      ),
    ),
  );
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.dot, required this.accent});

  final Offset? dot;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Size(:height, :width) = size;
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(
        Rect.fromLTWH(0, 0, width / 2, height),
        Paint()..color = accent,
      )
      ..drawRect(
        Rect.fromLTWH(width * 2 / 3, 0, width / 3, height),
        Paint()..color = const Color(0xFFFF5722),
      );
    if (dot case final point?) {
      canvas.drawRect(
        Rect.fromLTWH(point.dx, point.dy, 1, 1),
        Paint()..color = const Color(0xFF000000),
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) =>
      oldDelegate.dot != dot || oldDelegate.accent != accent;
}
