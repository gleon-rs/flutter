import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/config/golden_resolution.dart';
import 'package:gleon/src/core/native/native_engine.dart';
import 'package:gleon/src/core/native/native_report.dart';

void main() {
  test('a library of another ABI is refused with an actionable error', () {
    expect(
      () => NativeEngine.checkAbiVersion(NativeEngine.expectedAbiVersion),
      returnsNormally,
    );
    expect(
      () => NativeEngine.checkAbiVersion(NativeEngine.expectedAbiVersion - 1),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Rebuild the native library'),
        ),
      ),
    );
  });

  test(
    'malformed native JSON is an error for both contracts, never a pass',
    () {
      for (final bytes in [
        const [0xff, 0xfe],
        utf8.encode('{not json'),
        utf8.encode('null'),
      ]) {
        final decoded = NativeEngine.decodeReport(bytes);

        expect(NativeReport.parse(decoded, null), isA<NativeError>());
        expect(
          GoldenResolution.fromNativeJson(decoded),
          isA<GoldenResolutionError>(),
        );
      }
      expect(NativeEngine.decodeReport(utf8.encode('{"a":1}')), {'a': 1});
    },
  );
}
