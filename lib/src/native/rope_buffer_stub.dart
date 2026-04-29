/// Native C++ rope buffer wrapper.
///
/// This API is unavailable on non-FFI platforms (for example web).
class NativeRopeBuffer {
  /// Throws [UnsupportedError] on non-FFI platforms.
  factory NativeRopeBuffer.create() {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  /// Throws [UnsupportedError] on non-FFI platforms.
  int get lengthBytes {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  /// Throws [UnsupportedError] on non-FFI platforms.
  void append(String text) {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  /// Throws [UnsupportedError] on non-FFI platforms.
  String substring(int start, [int? end]) {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  /// Throws [UnsupportedError] on non-FFI platforms.
  void clear() {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  /// No-op on non-FFI platforms.
  void dispose() {}
}
