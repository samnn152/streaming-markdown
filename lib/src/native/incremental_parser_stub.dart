/// Native incremental markdown parser session.
///
/// This API is unavailable on non-FFI platforms (for example web).
class NativeIncrementalMarkdownParser {
  /// Throws [UnsupportedError] on non-FFI platforms.
  factory NativeIncrementalMarkdownParser.create() {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// Replaces the full source [text] and reparses the document.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  bool setText(String text) {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// Appends a streaming [text] chunk and reparses incrementally.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  bool appendText(String text) {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// Returns the current block-node count from native tree-sitter output.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  int blockCount() {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// Returns how many inline node types have been observed.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  int inlineTypeCount() {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// Returns flattened block nodes as decoded JSON maps.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  List<Map<String, Object>> blockNodes({int? maxNodes}) {
    throw UnsupportedError(
      'NativeIncrementalMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// No-op on non-FFI platforms.
  void dispose() {}
}
