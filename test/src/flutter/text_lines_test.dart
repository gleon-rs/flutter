import 'package:flutter/widgets.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';
import 'package:gleon/src/flutter/text_regions.dart';

const _boundaryKey = ValueKey<String>('boundary');

void main() {
  testWidgets('dense lines of mixed sizes keep a region each', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: .ltr,
        child: Align(
          alignment: .topLeft,
          child: RepaintBoundary(
            key: _boundaryKey,
            child: SizedBox(
              width: 100,
              height: 50,
              child: Align(
                alignment: .topLeft,
                child: SizedBox(
                  width: 40,
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 8,
                        height: 0.5,
                        fontFamily: 'FlutterTest',
                      ),
                      children: [
                        TextSpan(text: 'A ', style: TextStyle(fontSize: 40)),
                        TextSpan(text: 'bbbbbbbb'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The tight box of the big `A` (-15 to 25) reaches over the second line
    // (17 to 25), whose middle lies above its bottom: still a line of its
    // own (lines are told apart by the boxes of their full height).
    expect(
      TextRegions.captured(tester.element(find.byKey(_boundaryKey))),
      const [
        PixelRegion(x: 0, y: 0, width: 45, height: 30),
        PixelRegion(x: 0, y: 16, width: 41, height: 10),
        PixelRegion(x: 0, y: 20, width: 25, height: 9),
      ],
    );
  });
}
