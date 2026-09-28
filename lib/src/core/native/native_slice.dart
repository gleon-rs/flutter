import 'dart:ffi';

/// The safer-ffi `c_slice::Ref<u8>` returned by value: a borrowed view into a
/// `GleonResult` (`ptr` is null for "none"), valid until the result is freed.
final class NativeSlice extends Struct {
  /// First byte, or `nullptr` when the value is absent.
  external Pointer<Uint8> ptr;

  /// Number of bytes.
  @Size()
  external int len;
}
