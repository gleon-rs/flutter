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
  /// outwards). Only text its parents paint counts ([_PaintRecorder]): not
  /// the hidden children of an `IndexedStack`, `Offstage`, `Visibility` or a
  /// sliver, nor a route or overlay entry under an opaque one. A line a
  /// perspective transform sends to infinity is skipped too; empty text has
  /// no region.
  static List<PixelRegion> captured(Element element) {
    RenderObject? boundary = element.renderObject;
    while (boundary != null && !boundary.isRepaintBoundary) {
      boundary = boundary.parent;
    }
    if (boundary == null) return const [];
    final bounds = boundary.paintBounds;
    final painted = _PaintRecorder.paintedBy(boundary);
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
        final transformed = MatrixUtils.transformRect(toImage, line);
        final rect = transformed.intersect(clip);
        // A perspective can send a line to infinity (or NaN), which is not
        // painted; clipped, it would cover the whole clip.
        if (transformed.isFinite && !rect.isEmpty) {
          final Rect(:bottom, :left, :right, :top) = rect;
          regions.add(
            .outwards(left: left, top: top, right: right, bottom: bottom),
          );
        }
      }
      final children = <RenderObject>[];
      object.visitChildren(children.add);
      for (final child in children) {
        if (painted.contains(child)) {
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

  /// The lines of text of [object] in its own coordinates, grown by
  /// [margin] of their height and clipped to the object (grown the same)
  /// unless it paints its overflow; none for other render objects.
  static List<Rect> _lines(RenderObject object) => switch (object) {
    RenderParagraph(:final overflow, :final size, :final text) => _linesOf(
      text.toPlainText(includeSemanticsLabels: false),
      object.getBoxesForSelection,
      overflow == .visible ? null : Offset.zero & size,
    ),
    RenderEditable(:final plainText, :final size) => _linesOf(
      plainText,
      object.getBoxesForSelection,
      Offset.zero & size,
    ),
    _ => const [],
  };

  /// The lines of [plain] text whose selections [boxesOf] gives, clipped to
  /// [own] (null: the overflow is painted).
  static List<Rect> _linesOf(
    String plain,
    List<TextBox> Function(TextSelection selection) boxesOf,
    Rect? own,
  ) {
    final lines = <Rect>[];
    int start = 0;
    // The text between placeholders: a `WidgetSpan` is no text.
    for (final segment in plain.split(_placeholder)) {
      final end = start + segment.length;
      if (end > start) {
        lines.addAll(
          _byLine(boxesOf(TextSelection(baseOffset: start, extentOffset: end))),
        );
      }
      start = end + _placeholder.length;
    }

    // Text beyond its object is clipped (an ellipsis, a scrolled field),
    // unless a paragraph paints its overflow; tight boxes may reach a
    // fraction of a pixel beyond it.
    return [for (final line in lines) _grown(line, own)];
  }

  /// [line] grown by [margin] of its height, clipped to [own] grown the same.
  static Rect _grown(Rect line, Rect? own) {
    final delta = line.height * margin;
    final grown = line.inflate(delta);

    return own == null ? grown : grown.intersect(own.inflate(delta));
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
}

/// A render object to visit: the transform from its coordinates to the image,
/// and the clip of its ancestors in the image.
typedef _Painted = ({Rect clip, RenderObject object, Matrix4 toImage});

/// A paint of the render tree under a repaint boundary that only records which
/// render objects their parents paint (`paintChild`): the one sure sign that
/// text is visible, since not every render object that hides a child
/// overrides `paintsChild` (`IndexedStack`, `Visibility.maintain`, slivers,
/// the offstage entries of an overlay).
///
/// It draws into a throwaway picture and never adopts a live layer: children
/// are painted in place instead of being composited, pushed layers are not
/// appended anywhere, and every render object gets the offset of a real paint,
/// so the layers it updates keep their values and the frames after it render
/// as before.
final class _PaintRecorder extends PaintingContext {
  _PaintRecorder(ContainerLayer root, this._painted) : super(root, .largest);

  final Set<RenderObject> _painted;

  /// The render objects [boundary] paints, itself included, as of its last
  /// layout.
  static Set<RenderObject> paintedBy(RenderObject boundary) {
    final painted = <RenderObject>{boundary};
    final layer = ContainerLayer();
    final root = LayerHandle(layer);
    final recorder = _PaintRecorder(layer, painted);
    try {
      boundary.paint(recorder, .zero);
      recorder.stopRecordingIfNeeded();
    } finally {
      // Disposes the throwaway picture.
      root.layer = null;
    }

    return painted;
  }

  @override
  void paintChild(RenderObject child, Offset offset) {
    RenderObject painted = child;
    Offset paintOffset = offset;
    // A shader mask writes a new shader into its live layer on every paint,
    // which would mark it changed; it paints its child, if any, at its own
    // offset, so that child is painted instead.
    while (painted is RenderShaderMask) {
      // ignore: avoid-collection-mutating-methods, recording is its purpose.
      _painted.add(painted);
      paintOffset = painted.isRepaintBoundary ? .zero : paintOffset;
      final masked = painted.child;
      if (masked == null) return;
      painted = masked;
    }
    // ignore: avoid-collection-mutating-methods, recording is its purpose.
    _painted.add(painted);
    // In place, also a repaint boundary (compositing it would move its live
    // layer here), and with the offset of a real paint: a repaint boundary
    // paints at zero in its own layer. Render objects set their live layers
    // from the offset (a leader layer, an opacity layer): the same values
    // leave them as they are.
    painted.paint(this, painted.isRepaintBoundary ? .zero : paintOffset);
  }

  @override
  void pushLayer(
    ContainerLayer childLayer,
    PaintingContextCallback painter,
    Offset offset, {
    Rect? childPaintBounds,
  }) => painter(this, offset);

  // A path has no value equality, so writing the shifted path of a real paint
  // into the live layer of a path clip (an oval, a physical shape) over a
  // composited child would mark that layer changed. The clip draws nothing to
  // record; the painter gets the offset of a real paint, and the render
  // object keeps the layer it had.
  @override
  ClipPathLayer? pushClipPath(
    bool needsCompositing,
    Offset offset,
    Rect bounds,
    Path clipPath,
    PaintingContextCallback painter, {
    Clip clipBehavior = .antiAlias,
    ClipPathLayer? oldLayer,
  }) {
    painter(this, offset);

    return needsCompositing && clipBehavior != .none ? oldLayer : null;
  }

  // A live layer is never adopted: a platform view or texture paints no text.
  @override
  // ignore: no-empty-block, nothing to record.
  void addLayer(Layer layer) {}
}
