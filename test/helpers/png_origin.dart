import 'dart:convert';
import 'dart:typed_data';

/// The platform a golden PNG was recorded on, as gleon stamps it: a `tEXt`
/// chunk `gleon:platform` right after the header (`gleon_model::origin` in
/// the gleon repository). Test-only: the package never reads PNGs itself.
abstract final class PngOrigin {
  /// The keyword of the stamp.
  static const keyword = 'gleon:platform';

  /// The platform [png] names, or null without a stamp.
  static String? read(Uint8List png) {
    for (final chunk in _chunks(png)) {
      if (_isStamp(chunk)) {
        return latin1.decode(chunk.data.sublist(_prefix.length));
      }
    }

    return null;
  }

  /// [png] stamped as recorded on [platform] (any earlier stamp dropped),
  /// like gleon writes it.
  static Uint8List stamp(Uint8List png, String platform) {
    final type = latin1.encode('tEXt');
    final text = latin1.encode('$_prefix$platform');
    final out = BytesBuilder(copy: false)..add(png.sublist(0, 8));
    for (final chunk in _chunks(png)) {
      if (!_isStamp(chunk)) out.add(chunk.bytes);
      if (chunk.type == 'IHDR') {
        out
          ..add(_u32(text.length))
          ..add(type)
          ..add(text)
          ..add(_u32(_crc32([...type, ...text])));
      }
    }

    return out.takeBytes();
  }

  static const _prefix = '$keyword\u0000';

  static bool _isStamp(_Chunk chunk) =>
      chunk.type == 'tEXt' && latin1.decode(chunk.data).startsWith(_prefix);

  static Iterable<_Chunk> _chunks(Uint8List png) sync* {
    final view = ByteData.sublistView(png);
    int offset = 8;
    while (offset + 8 <= png.length) {
      final length = view.getUint32(offset);
      final end = offset + length + 12;
      if (end > png.length) return;
      yield (
        bytes: png.sublist(offset, end),
        data: png.sublist(offset + 8, end - 4),
        type: latin1.decode(png.sublist(offset + 4, offset + 8)),
      );
      offset = end;
    }
  }

  static Uint8List _u32(int value) =>
      .new(4)..buffer.asByteData().setUint32(0, value);

  static int _crc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (int bit = 0; bit < 8; bit += 1) {
        crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }

    return crc ^ 0xFFFFFFFF;
  }
}

/// One chunk of a PNG: all its bytes, its data and its type.
typedef _Chunk = ({Uint8List bytes, Uint8List data, String type});
