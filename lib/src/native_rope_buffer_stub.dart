/// Native C++ rope buffer wrapper.
///
/// This API is unavailable on non-FFI platforms (for example web).
class NativeRopeBuffer {
  factory NativeRopeBuffer.create() {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  int get lengthBytes {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  void append(String text) {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  String substring(int start, [int? end]) {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  void clear() {
    throw UnsupportedError(
      'NativeRopeBuffer is only available on FFI-enabled platforms.',
    );
  }

  void dispose() {}
}
