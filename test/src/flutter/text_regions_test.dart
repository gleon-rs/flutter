import 'package:flutter/widgets.dart';
import 'package:gleon/gleon.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';
import 'package:gleon/src/flutter/text_regions.dart';

// Flutter's test font: every glyph is a square of the font size.
const _style = TextStyle(fontSize: 10, fontFamily: 'FlutterTest');

const _boundaryKey = ValueKey<String>('boundary');

const _empty = '';

List<PixelRegion> _regions(WidgetTester tester, [Finder? finder]) =>
    TextRegions.captured(tester.element(finder ?? find.byKey(_boundaryKey)));

void main() {
  testWidgets('a region hugs the text, not its widget', (tester) async {
    await tester.pumpWidget(
      const _Boundary(
        Padding(
          padding: .only(left: 3, top: 4),
          child: Text('abc', style: _style, textAlign: .center),
        ),
      ),
    );

    // 30x10 centered in the 97px after the padding: x 36.5 to 66.5, grown
    // by the margin (1.25px of the 10px line) and rounded outwards.
    expect(_regions(tester), const [
      PixelRegion(x: 35, y: 2, width: 33, height: 14),
    ]);
  });

  testWidgets('unpainted or empty text has no region', (tester) async {
    await tester.pumpWidget(
      const _Boundary(
        Column(
          children: [
            Offstage(
              child: ExcludeFocus(child: Text('hidden', style: _style)),
            ),
            Text(_empty, style: _style),
          ],
        ),
      ),
    );

    expect(_regions(tester), isEmpty);
  });

  testWidgets('text sent to infinity has no region', (tester) async {
    // A perspective with w = 0 everywhere: no transformed line is finite.
    final degenerate = Matrix4.identity()..setEntry(3, 3, 0);
    await tester.pumpWidget(
      _Boundary(
        Column(
          children: [
            Transform(
              transform: degenerate,
              child: const Text('far', style: _style),
            ),
            const Text('near', style: _style),
          ],
        ),
      ),
    );

    expect(_regions(tester), hasLength(1));
  });

  testWidgets('editable text has a region', (tester) async {
    final controller = TextEditingController(text: 'ab');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _Boundary(
        EditableText(
          controller: controller,
          focusNode: focusNode,
          style: _style,
          cursorColor: const Color(0xFF000000),
          backgroundCursorColor: const Color(0xFF808080),
          autofillHints: null,
        ),
      ),
    );

    // 20x10 and the margin, clipped to the image.
    expect(_regions(tester), const [
      PixelRegion(x: 0, y: 0, width: 22, height: 12),
    ]);
  });

  testWidgets('the root view captures physical pixels', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: .ltr,
        child: Align(
          alignment: .topLeft,
          child: Text('ab', key: ValueKey('text'), style: _style),
        ),
      ),
    );

    // A 20x10 text and its margin at Flutter tests' default device pixel
    // ratio of 3, clipped to the image.
    expect(tester.view.devicePixelRatio, 3);
    expect(_regions(tester, find.byKey(const ValueKey('text'))), const [
      PixelRegion(x: 0, y: 0, width: 64, height: 34),
    ]);
  });

  testWidgets('one region per line, none over a WidgetSpan', (tester) async {
    await tester.pumpWidget(
      const _Boundary(
        Align(
          alignment: .topLeft,
          child: SizedBox(
            width: 50,
            child: Text.rich(
              TextSpan(
                style: _style,
                children: [
                  TextSpan(text: 'ab '),
                  WidgetSpan(child: SizedBox.square(dimension: 10)),
                  TextSpan(text: ' cd ef'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // `ab ` (30px), the 10px placeholder, ` ` fill the 50px of the first line,
    // `cd ef` the second; each line of text grown by the margin, clipped to
    // the image and the paragraph (and its margin).
    expect(_regions(tester), const [
      PixelRegion(x: 0, y: 0, width: 32, height: 12),
      PixelRegion(x: 38, y: 0, width: 14, height: 12),
      PixelRegion(x: 0, y: 8, width: 52, height: 14),
    ]);
  });

  testWidgets('text of mixed sizes on one line is one region', (tester) async {
    await tester.pumpWidget(
      const _Boundary(
        Align(
          alignment: .topLeft,
          child: Text.rich(
            TextSpan(
              style: _style,
              children: [
                TextSpan(text: 'ab'),
                TextSpan(text: 'C', style: TextStyle(fontSize: 28)),
                TextSpan(text: 'de'),
              ],
            ),
          ),
        ),
      ),
    );

    // On the baseline of the 28px `C`, the 10px runs lie within its line:
    // 68x28 grown by 3.5px, clipped to the image.
    expect(_regions(tester), const [
      PixelRegion(x: 0, y: 0, width: 72, height: 32),
    ]);
  });

  testWidgets('text side by side keeps the gap between', (tester) async {
    await tester.pumpWidget(
      const _Boundary(
        Row(
          mainAxisAlignment: .spaceBetween,
          crossAxisAlignment: .start,
          children: [
            Text('ab', style: _style),
            SizedBox.square(dimension: 10),
            Text('cd', style: _style),
          ],
        ),
      ),
    );

    // Lines merge within a paragraph only: two columns on one line are two
    // regions, and what lies between them (an icon) is still compared.
    expect(
      _regions(tester),
      unorderedEquals(const [
        PixelRegion(x: 0, y: 0, width: 22, height: 12),
        PixelRegion(x: 78, y: 0, width: 22, height: 12),
      ]),
    );
  });

  testWidgets('clipped text is clipped', (tester) async {
    await tester.pumpWidget(
      const _Boundary(
        Align(
          alignment: .topLeft,
          child: Column(
            crossAxisAlignment: .start,
            children: [
              // An ellipsis: the elided text has boxes beyond the paragraph.
              SizedBox(
                width: 30,
                child: Text(
                  'abcdefgh',
                  style: _style,
                  overflow: .ellipsis,
                  maxLines: 1,
                ),
              ),
              // An ancestor clip: only 4px of the line are painted.
              ClipRect(
                child: SizedBox(
                  height: 4,
                  child: OverflowBox(
                    alignment: .topLeft,
                    maxHeight: 20,
                    child: Text('ab', style: _style),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(_regions(tester), const [
      PixelRegion(x: 0, y: 10, width: 22, height: 4),
      PixelRegion(x: 0, y: 0, width: 32, height: 12),
    ]);
  });
}

/// A 100x50 repaint boundary at the top left around [child].
class _Boundary extends StatelessWidget {
  const _Boundary(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: .ltr,
    child: Align(
      alignment: .topLeft,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: SizedBox(width: 100, height: 50, child: child),
      ),
    ),
  );
}
