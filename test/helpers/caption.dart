import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real text (Roboto, `loadAppFonts`) between solid shapes: a heading, a
/// wrapped paragraph and a row of digits, under a bar and beside a box. Each
/// parameter is a mutation the text tolerance must still catch.
class Caption extends StatelessWidget {
  /// Creates the caption; the defaults render its golden.
  const Caption({
    this.paragraph = sample,
    this.digits = '0123456789',
    this.color = const Color(0xFF000000),
    this.weight = FontWeight.w400,
    this.shift = 0,
    this.hasFrame = false,
    super.key,
  });

  /// Key of the captured boundary.
  static const boundaryKey = ValueKey<String>('caption');

  /// Its golden, relative to the test files (recorded on macOS).
  static const golden = 'goldens/caption.png';

  /// The paragraph of the golden.
  static const sample =
      'Press Submit to send the form, the quick brown fox jumps over the '
      'lazy dog; Cancel keeps your draft.';

  /// Finds the captured boundary.
  static Finder get finder => find.byKey(boundaryKey);

  /// The wrapped paragraph.
  final String paragraph;

  /// The row of digits (Roboto's digits all have the same width).
  final String digits;

  /// Color of the text.
  final Color color;

  /// Weight of the paragraph.
  final FontWeight weight;

  /// Horizontal shift of the paragraph, in pixels.
  final double shift;

  /// Whether a 1px frame is drawn tightly around the digits.
  final bool hasFrame;

  TextStyle _style(double size, FontWeight fontWeight) => .new(
    color: color,
    fontSize: size,
    fontWeight: fontWeight,
    fontFamily: 'Roboto',
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('paragraph', paragraph))
      ..add(StringProperty('digits', digits))
      ..add(ColorProperty('color', color))
      ..add(DiagnosticsProperty<FontWeight>('weight', weight))
      ..add(DoubleProperty('shift', shift))
      ..add(FlagProperty('hasFrame', value: hasFrame, ifTrue: 'framed'));
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: .ltr,
    child: Align(
      alignment: .topLeft,
      child: RepaintBoundary(
        key: boundaryKey,
        child: Container(
          padding: const .all(12),
          color: const Color(0xFFFFFFFF),
          width: 240,
          height: 160,
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              const SizedBox(
                width: .infinity,
                height: 6,
                child: ColoredBox(color: Color(0xFF2196F3)),
              ),
              Column(
                crossAxisAlignment: .start,
                children: [
                  Text('Invoice', style: _style(20, .w700)),
                  Padding(
                    padding: .only(left: shift),
                    child: Text(paragraph, style: _style(12, weight)),
                  ),
                ],
              ),
              Row(
                spacing: 8,
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: ColoredBox(color: Color(0xFFFF5722)),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: hasFrame ? .all(color: color) : null,
                    ),
                    child: Text(digits, style: _style(14, .w400)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
