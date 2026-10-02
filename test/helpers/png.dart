import 'dart:io';
import 'dart:typed_data';

/// The pixels of an 8-bit, non-interlaced RGBA PNG (what Flutter's encoder
/// writes), decoded without an image library, so nothing between the file and
/// the bytes can premultiply or convert them.
///
/// Throws a [FormatException] for any other kind of PNG.
({int height, Uint8List rgba, int width}) decodeRgbaPng(Uint8List png) {
  final data = ByteData.sublistView(png);
  final compressed = BytesBuilder(copy: false);
  int? width;
  int? height;
  // After the 8-byte signature: chunks of length, type, body and CRC.
  for (int offset = 8; offset < png.length;) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(png, offset + 4, offset + 8);
    final body = offset + 8;
    if (type == 'IHDR') {
      width = data.getUint32(body);
      height = data.getUint32(body + 4);
      final (depth, color, interlace) = (
        data.getUint8(body + 8),
        data.getUint8(body + 9),
        data.getUint8(body + 12),
      );
      if (depth != 8 || color != 6 || interlace != 0) {
        throw FormatException(
          'not an 8-bit non-interlaced RGBA PNG: depth $depth, '
          'color type $color, interlace $interlace',
        );
      }
    } else if (type == 'IDAT') {
      compressed.add(Uint8List.sublistView(png, body, body + length));
    }
    offset = body + length + 4;
  }
  if (width == null || height == null) {
    throw const FormatException('no IHDR chunk');
  }

  final filtered = Uint8List.fromList(zlib.decode(compressed.takeBytes()));

  return (
    height: height,
    rgba: _unfilter(ByteData.sublistView(filtered), width, height),
    width: width,
  );
}

/// Reverses the per-row PNG filters of 4-byte pixels.
Uint8List _unfilter(ByteData filtered, int width, int height) {
  const bytesPerPixel = 4;
  final stride = width * bytesPerPixel;
  final pixels = ByteData(stride * height);
  for (int row = 0; row < height; row += 1) {
    final source = row * (stride + 1);
    final filter = filtered.getUint8(source);
    final start = row * stride;
    for (int i = 0; i < stride; i += 1) {
      final hasLeft = i >= bytesPerPixel;
      final left = hasLeft ? pixels.getUint8(start + i - bytesPerPixel) : 0;
      final above = row > 0 ? pixels.getUint8(start - stride + i) : 0;
      final aboveLeft = row > 0 && hasLeft
          ? pixels.getUint8(start - stride + i - bytesPerPixel)
          : 0;
      final predicted = switch (filter) {
        0 => 0,
        1 => left,
        2 => above,
        3 => (left + above) >> 1,
        4 => _paeth(left, above, aboveLeft),
        _ => throw FormatException('unknown PNG filter $filter in row $row'),
      };
      pixels.setUint8(
        start + i,
        (filtered.getUint8(source + 1 + i) + predicted) & 0xFF,
      );
    }
  }

  return Uint8List.sublistView(pixels);
}

int _paeth(int left, int above, int aboveLeft) {
  final estimate = left + above - aboveLeft;
  final toLeft = (estimate - left).abs();
  final toAbove = (estimate - above).abs();
  final toAboveLeft = (estimate - aboveLeft).abs();
  if (toLeft <= toAbove && toLeft <= toAboveLeft) return left;

  return toAbove <= toAboveLeft ? above : aboveLeft;
}
