import 'dart:ffi';

/// Opaque `GleonResult` owned by the native library: created by
/// `gleon_compare`, released only by `gleon_result_free`.
final class GleonResult extends Opaque {}
