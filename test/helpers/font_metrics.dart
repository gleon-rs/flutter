import 'dart:typed_data';

/// A copy of the TrueType/OpenType [font] whose Windows line metrics are its
/// `hhea` ones, so text lays out alike on every OS.
///
/// macOS (CoreText) and Linux (FreeType) take a font's ascent and descent from
/// `hhea`, Windows (DirectWrite) from `OS/2` `usWinAscent`/`usWinDescent`;
/// Roboto has 1900/500 there and 1946/512 here (of 2048 units), so on Windows
/// every line is taller and every baseline lower. The `OS/2` table checksum
/// and the font's `checkSumAdjustment` are recomputed. A font collection, or a
/// font without these tables, is returned unchanged.
Uint8List withPortableLineMetrics(Uint8List font) {
  final copy = Uint8List.fromList(font);
  final data = ByteData.sublistView(copy);
  if (copy.length < 12 || String.fromCharCodes(copy, 0, 4) == 'ttcf') {
    return copy;
  }
  final tables = <String, ({int length, int offset, int record})>{};
  for (int index = 0; index < data.getUint16(4); index += 1) {
    final record = index * 16 + 12;
    tables[String.fromCharCodes(copy, record, record + 4)] = (
      length: data.getUint32(record + 12),
      offset: data.getUint32(record + 8),
      record: record,
    );
  }
  final (hhea, os2, head) = (tables['hhea'], tables['OS/2'], tables['head']);
  if (hhea == null || os2 == null || head == null || os2.length < 78) {
    return copy;
  }

  final above = data.getInt16(hhea.offset + 4);
  final below = -data.getInt16(hhea.offset + 6);
  data
    ..setUint16(os2.offset + 74, above.clamp(0, 0xFFFF))
    ..setUint16(os2.offset + 76, below.clamp(0, 0xFFFF))
    ..setUint32(os2.record + 4, openTypeChecksum(data, os2.offset, os2.length))
    // The whole-font checksum is taken with the adjustment itself zeroed.
    ..setUint32(head.offset + 8, 0)
    ..setUint32(
      head.offset + 8,
      (0xB1B0AFBA - openTypeChecksum(data, 0, copy.length)) & 0xFFFFFFFF,
    );

  return copy;
}

/// The OpenType checksum of [length] bytes at [offset]: the sum of big-endian
/// 32-bit words, the last one padded with zeros.
int openTypeChecksum(ByteData data, int offset, int length) {
  final end = offset + length;
  int sum = 0;
  for (int word = offset; word < end; word += 4) {
    int value = 0;
    for (int byte = 0; byte < 4; byte += 1) {
      final position = word + byte;
      value = (value << 8) | (position < end ? data.getUint8(position) : 0);
    }
    sum = (sum + value) & 0xFFFFFFFF;
  }

  return sum;
}
