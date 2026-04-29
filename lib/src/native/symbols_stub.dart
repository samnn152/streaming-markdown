/// Native dynamic library basename used by this package.
const String streamingMarkdownLibraryName = 'animated_streaming_markdown';

/// Whether the native library can be loaded on the current platform.
///
/// Always `false` on non-FFI platforms.
bool get isStreamingMarkdownNativeLibraryAvailable => false;
