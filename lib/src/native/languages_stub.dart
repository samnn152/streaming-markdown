/// Returns the native tree-sitter Markdown language pointer.
///
/// Throws [UnsupportedError] on non-FFI platforms.
Never markdownLanguage() {
  throw UnsupportedError(
    'markdownLanguage() is only available on FFI-enabled platforms.',
  );
}

/// Returns the native tree-sitter Markdown inline language pointer.
///
/// Throws [UnsupportedError] on non-FFI platforms.
Never markdownInlineLanguage() {
  throw UnsupportedError(
    'markdownInlineLanguage() is only available on FFI-enabled platforms.',
  );
}
