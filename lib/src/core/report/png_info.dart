import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// Identity of a PNG for case reports: its SHA-256 and, when the header is
/// readable, its size (read from the `IHDR` chunk without decoding).
@immutable
final class PngInfo {
  /// Creates the info.
  const PngInfo({required this.sha256, this.width, this.height});

  /// Hashes [bytes] and reads the size from the PNG header.
  factory PngInfo.of(Uint8List bytes) {
    final digest = crypto.sha256.convert(bytes).toString();
    // Signature (8 bytes), IHDR length (4) and type (4), then width, height.
    // ignore: avoid-duplicate-collection-elements, the PNG signature.
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const ihdr = [0x49, 0x48, 0x44, 0x52];
    final hasHeader =
        bytes.length >= 24 &&
        _hasBytesAt(bytes, signature, 0) &&
        _hasBytesAt(bytes, ihdr, 12);
    if (!hasHeader) return PngInfo(sha256: digest);
    final header = ByteData.sublistView(bytes, 16, 24);

    return PngInfo(
      sha256: digest,
      width: header.getUint32(0),
      height: header.getUint32(4),
    );
  }

  /// Lowercase hex SHA-256 of the PNG bytes.
  final String sha256;

  /// Width in pixels, when the header is readable.
  final int? width;

  /// Height in pixels, when the header is readable.
  final int? height;

  /// `{sha256, width?, height?}` as in the case report schema.
  Map<String, Object> toJson() => {
    'height': ?height,
    'sha256': sha256,
    'width': ?width,
  };

  static bool _hasBytesAt(Uint8List bytes, List<int> expected, int offset) {
    for (final (index, expectedByte) in expected.indexed) {
      if (bytes.elementAtOrNull(offset + index) != expectedByte) return false;
    }

    return true;
  }
}
