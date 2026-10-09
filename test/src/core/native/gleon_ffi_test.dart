import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/native/gleon_ffi.dart';
import 'package:gleon/src/core/native/native_engine.dart';

import '../../../helpers/workspace_sandbox.dart';

/// `gleon-ffi/src/lib.rs` of the pinned commit (`gleonPin`) in a sibling
/// gleon checkout (`../gleon`, as in CI), or null without that checkout or
/// commit.
String? _pinnedLib() {
  try {
    final shown = Process.runSync('git', [
      '-C',
      '../gleon',
      'show',
      '$gleonPin:gleon-ffi/src/lib.rs',
    ]);

    return shown.exitCode == 0 ? '${shown.stdout}' : null;
  } on ProcessException {
    return null;
  }
}

/// The byte offset [write] puts a non-zero value at, in a zeroed struct of
/// [size] bytes.
int _offset(int size, void Function(Uint8List bytes) write) {
  final bytes = Uint8List(size);
  write(bytes);

  return bytes.indexWhere((byte) => byte != 0);
}

/// The offset of each field of `GleonCall` as Dart writes it, by its Rust
/// name.
Map<String, int> _callOffsets() {
  int offset(void Function(Uint8List bytes) write) =>
      _offset(sizeOf<GleonCall>(), write);

  return {
    'candidate_format': offset(
      (bytes) => Struct.create<GleonCall>(bytes).candidateFormat = 1,
    ),
    'candidate_height': offset(
      (bytes) => Struct.create<GleonCall>(bytes).candidateHeight = 1,
    ),
    'candidate_width': offset(
      (bytes) => Struct.create<GleonCall>(bytes).candidateWidth = 1,
    ),
    'color_tolerance': offset(
      (bytes) => Struct.create<GleonCall>(bytes).colorTolerance = 1 / 3,
    ),
    'max_diff_ratio': offset(
      (bytes) => Struct.create<GleonCall>(bytes).maxDiffRatio = 1 / 3,
    ),
    'min_similarity': offset(
      (bytes) => Struct.create<GleonCall>(bytes).minSimilarity = 1 / 3,
    ),
    'mode': offset((bytes) => Struct.create<GleonCall>(bytes).mode = 1),
    'text_tolerance': offset(
      (bytes) => Struct.create<GleonCall>(bytes).textTolerance = 1 / 3,
    ),
    'tolerance_kind': offset(
      (bytes) => Struct.create<GleonCall>(bytes).toleranceKind = 1,
    ),
  };
}

/// The offset of each field of `GleonSummary` as Dart reads it, by its Rust
/// name (a slice by its pointer, its first member).
Map<String, int> _summaryOffsets() {
  int offset(void Function(Uint8List bytes) write) =>
      _offset(sizeOf<GleonSummary>(), write);
  final Pointer<Never> set = .fromAddress(1);

  return {
    'console': offset(
      (bytes) =>
          Struct.create<GleonSummary>(bytes).console.ptr = set.cast<Uint8>(),
    ),
    'error_kind': offset(
      (bytes) => Struct.create<GleonSummary>(bytes).errorKind = 1,
    ),
    'message': offset(
      (bytes) =>
          Struct.create<GleonSummary>(bytes).message.ptr = set.cast<Uint8>(),
    ),
    'texts': offset(
      (bytes) =>
          Struct.create<GleonSummary>(bytes).texts = set.cast<GleonTexts>(),
    ),
    'verdict': offset(
      (bytes) => Struct.create<GleonSummary>(bytes).verdict = 1,
    ),
    'warning': offset(
      (bytes) =>
          Struct.create<GleonSummary>(bytes).warning.ptr = set.cast<Uint8>(),
    ),
  };
}

const _noSource = '';

void main() {
  // The layout the library asserts next to its structs (`gleon-ffi/src/
  // lib.rs`): the Dart declarations must match it field by field.
  test('the structs have the layout of gleon-ffi', () {
    expect(sizeOf<GleonCall>(), 48);
    expect(_callOffsets(), {
      'candidate_format': 41,
      'candidate_height': 36,
      'candidate_width': 32,
      'color_tolerance': 16,
      'max_diff_ratio': 0,
      'min_similarity': 8,
      'mode': 40,
      'text_tolerance': 24,
      'tolerance_kind': 42,
    });
    expect(sizeOf<GleonSummary>(), 64);
    expect(_summaryOffsets(), {
      'console': 24,
      'error_kind': 1,
      'message': 8,
      'texts': 56,
      'verdict': 0,
      'warning': 40,
    });
  });

  // The pinned library itself: its ABI version and the layout it asserts,
  // read from its source, so a pin bump that changes either fails here
  // instead of in every golden.
  final lib = _pinnedLib();
  test(
    'the pinned gleon-ffi speaks the ABI and layout of these bindings',
    () {
      final source = lib ?? _noSource;
      final abi = RegExp(r'ABI_VERSION: u32 = (\d+);').firstMatch(source);
      expect(abi?.group(1), '${NativeEngine.expectedAbiVersion}');
      final asserted = <String, Map<String, int>>{};
      for (final match in RegExp(
        r'offset_of!\((\w+), (\w+)\) == (\d+)',
      ).allMatches(source)) {
        if ((match.group(1), match.group(2), match.group(3)) case (
          final type?,
          final field?,
          final offset?,
        )) {
          asserted.putIfAbsent(type, () => {})[field] = int.parse(offset);
        }
      }
      expect(asserted, {
        'GleonCall': _callOffsets(),
        'GleonSummary': _summaryOffsets(),
      });
    },
    skip: lib == null || !lib.contains('offset_of!')
        ? 'needs ../gleon at a pin with the layout assertions'
        : false,
  );
}
