/// Native incremental markdown parser session.
///
/// This API is unavailable on non-FFI platforms (for example web).
class NativeIncrementalMarkdownParser {
  factory NativeIncrementalMarkdownParser.create() {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  bool setText(String text) {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  bool appendText(String text) {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  int blockCount() {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  int inlineTypeCount() {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  List<Map<String, Object>> blockNodes({int? maxNodes}) {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  void dispose() {}
}
