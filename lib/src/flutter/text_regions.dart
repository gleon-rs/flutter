import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show Element;

import '../core/compare/pixel_region.dart';

/// Where a captured widget paints text, for the text tolerance.
abstract final class TextRegions {
  /// The share of its height added around every line of text: glyph ink
  /// reaches beyond the boxes of its line (diacritics, negative letter
  /// spacing, outlined text) by an amount that grows with the font, and
  /// anti-aliasing beyond that.
  static const margin = 0.125;

  /// The character a `WidgetSpan` takes in the text.
  static final _placeholder = String.fromCharCode(0xFFFC);

  /// The boxes of text in the image `captureImage` takes of [element]: its
  /// closest repaint boundary, at a pixel ratio of 1.
  ///
  /// One region per line of each paragraph and editable text painted there:
  /// the boxes of the line's text (not of its `WidgetSpan`s), grown by
  /// [margin] of its height, clipped by the paragraph (when its text
  /// overflows) and by its ancestors, in whole pixels of the image (rounded
  /// outwards). Text in
  /// children that are not painted (`Offstage`, `Visibility`) is skipped;
  /// empty text has no region.
  static List<PixelRegion> captured(Element element) {
    RenderObject? boundary = element.renderObject;
    while (boundary != null && !boundary.isRepaintBoundary) {
      boundary = boundary.parent;
    }
    if (boundary == null) return const [];
    final bounds = boundary.paintBounds;
    final regions = <PixelRegion>[];
    // Render objects with the transform from their coordinates to the image
    // and the clip of their ancestors in the image.
    final pending = <_Painted>[
      (
        clip: Offset.zero & bounds.size,
        object: boundary,
        toImage: Matrix4.translationValues(-bounds.left, -bounds.top, 0),
      ),
    ];
    while (pending.isNotEmpty) {
      final (:clip, :object, :toImage) = pending.removeLast();
      for (final line in _lines(object)) {
        final rect = MatrixUtils.transformRect(toImage, line).intersect(clip);
        if (!rect.isEmpty) regions.add(_outwards(rect));
      }
      final children = <RenderObject>[];
      object.visitChildren(children.add);
      for (final child in children) {
        if (object.paintsChild(child) && _isSized(child)) {
          pending.add(_child(object, child, toImage, clip));
        }
      }
    }

    return regions;
  }

  /// [child] as [parent] paints it, given the transform and clip of [parent].
  static _Painted _child(
    RenderObject parent,
    RenderObject child,
    Matrix4 toImage,
    Rect clip,
  ) {
    final transform = toImage.clone();
    parent.applyPaintTransform(child, transform);
    final childClip = parent.describeApproximatePaintClip(child);

    return (
      clip: childClip == null
          ? clip
          : MatrixUtils.transformRect(toImage, childClip).intersect(clip),
      object: child,
      toImage: transform,
    );
  }

  /// Whether [object] has a size, or needs none.
  static bool _isSized(RenderObject object) =>
      object is! RenderBox || object.hasSize;

  /// The lines of text of [object] in its own coordinates, grown by
  /// [margin] of their height and clipped to the object (grown the same)
  /// unless it paints its overflow; none for other render objects.
  static List<Rect> _lines(RenderObject object) {
    final (:plain, :size) = switch (object) {
      RenderParagraph(:final text) => (
        plain: text.toPlainText(includeSemanticsLabels: false),
        size: object.size,
      ),
      RenderEditable(:final plainText) => (plain: plainText, size: object.size),
      _ => (plain: _noText, size: Size.zero),
    };
    final lines = <Rect>[];
    int start = 0;
    // The text between placeholders: a `WidgetSpan` is no text.
    for (final segment in plain.split(_placeholder)) {
      final end = start + segment.length;
      if (end > start) {
        lines.addAll(_byLine(_boxes(object, start, end)));
      }
      start = end + _placeholder.length;
    }
    // Text beyond its object is clipped (an ellipsis, a scrolled field),
    // unless a paragraph paints its overflow; tight boxes may reach a
    // fraction of a pixel beyond it.
    final isOverflowPainted =
        object is RenderParagraph && object.overflow == .visible;

    return [
      for (final line in lines)
        _grown(line, isOverflowPainted ? null : Offset.zero & size),
    ];
  }

  /// [line] grown by [margin] of its height, clipped to [own] grown the same.
  static Rect _grown(Rect line, Rect? own) {
    final delta = line.height * margin;
    final grown = line.inflate(delta);

    return own == null ? grown : grown.intersect(own.inflate(delta));
  }

  static const _noText = '';

  /// The boxes of the text from [start] to [end] of [object].
  static List<TextBox> _boxes(RenderObject object, int start, int end) {
    final selection = TextSelection(baseOffset: start, extentOffset: end);

    return switch (object) {
      RenderParagraph() => object.getBoxesForSelection(selection),
      RenderEditable() => object.getBoxesForSelection(selection),
      _ => const [],
    };
  }

  /// [boxes] merged into one rectangle per line: a box whose middle is within
  /// the line so far (tight boxes of adjacent lines may overlap a little).
  static List<Rect> _byLine(List<TextBox> boxes) {
    final rects = [for (final box in boxes) box.toRect()]
      ..sort((a, b) => a.top.compareTo(b.top));
    final lines = <Rect>[];
    Rect? current;
    for (final rect in rects) {
      if (current != null && rect.center.dy < current.bottom) {
        current = current.expandToInclude(rect);
      } else {
        if (current != null) lines.add(current);
        current = rect;
      }
    }

    return [...lines, ?current];
  }

  /// [rect] grown to whole pixels.
  static PixelRegion _outwards(Rect rect) {
    final Rect(:bottom, :left, :right, :top) = rect;
    final x = left.floor();
    final y = top.floor();

    return .new(x: x, y: y, width: right.ceil() - x, height: bottom.ceil() - y);
  }
}

/// A render object to visit: the transform from its coordinates to the image,
/// and the clip of its ancestors in the image.
typedef _Painted = ({Rect clip, RenderObject object, Matrix4 toImage});
