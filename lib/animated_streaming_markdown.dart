/// Animated streaming Markdown public API.
///
/// The package provides two layers:
/// - incremental parsing through [MarkdownStreamParser]
/// - Flutter rendering through [AnimatedStreamingMarkdown]
///
/// `0.3.x` introduces clearer API names while keeping the `0.2.x` names
/// available for migration.
///
/// Typical flow:
/// 1. Create and start a [MarkdownStreamParser].
/// 2. Call `replace(markdown)` for a full snapshot or `append(chunk)` for a
///    streamed chunk.
/// 3. Render `result.blocks` with [AnimatedStreamingMarkdown].
library animated_streaming_markdown;

/// Native UTF-8 rope buffer implementation backed by C++.
export 'src/native_rope_buffer_stub.dart'
    if (dart.library.ffi) 'src/native_rope_buffer.dart';

/// Native library availability and resolved library name for current platform.
export 'src/native_symbols_stub.dart'
    if (dart.library.ffi) 'src/native_symbols.dart'
    show
        isStreamingMarkdownNativeLibraryAvailable,
        streamingMarkdownLibraryName;

/// Basic markdown block node model used by pure-Dart rope parsing.
export 'src/markdown_nodes.dart';

/// Tree-sitter syntax tree model.
export 'src/markdown_syntax_tree.dart';

/// Render node model used by streaming render pipeline.
export 'src/markdown_render_node.dart';

/// Native incremental markdown parser session API.
export 'src/native_incremental_markdown_parser_stub.dart'
    if (dart.library.ffi) 'src/native_incremental_markdown_parser.dart';

/// Pure-Dart rope markdown parser.
export 'src/rope_markdown_parser.dart';

/// Append-friendly pure-Dart rope string.
export 'src/rope_string.dart';

/// Isolate worker wrapper for incremental parsing and render-node extraction.
export 'src/streaming_markdown_parse_worker_stub.dart'
    if (dart.library.ffi) 'src/streaming_markdown_parse_worker.dart';

/// Flutter markdown rendering widgets with streaming token animation support.
export 'src/streaming_markdown_render_view.dart';

/// Tree-sitter markdown parser API returning full syntax trees.
export 'src/tree_sitter_markdown_parser_stub.dart'
    if (dart.library.ffi) 'src/tree_sitter_markdown_parser.dart';

/// Native tree-sitter language pointer helpers.
///
/// On non-FFI platforms (for example web), these APIs throw
/// [UnsupportedError].
export 'src/native_languages_stub.dart'
    if (dart.library.ffi) 'src/native_languages_ffi.dart';
