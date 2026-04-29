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
export 'src/native/rope_buffer_stub.dart'
    if (dart.library.ffi) 'src/native/rope_buffer.dart';

/// Native library availability and resolved library name for current platform.
export 'src/native/symbols_stub.dart'
    if (dart.library.ffi) 'src/native/symbols.dart'
    show
        isStreamingMarkdownNativeLibraryAvailable,
        streamingMarkdownLibraryName;

/// Basic markdown block node model used by pure-Dart rope parsing.
export 'src/model/block_nodes.dart';

/// Tree-sitter syntax tree model.
export 'src/model/syntax_tree.dart';

/// Render node model used by streaming render pipeline.
export 'src/model/render_node.dart';

/// Native incremental markdown parser session API.
export 'src/native/incremental_parser_stub.dart'
    if (dart.library.ffi) 'src/native/incremental_parser.dart';

/// Pure-Dart rope markdown parser.
export 'src/parser/rope_markdown_parser.dart';

/// Append-friendly pure-Dart rope string.
export 'src/model/rope.dart';

/// Isolate worker wrapper for incremental parsing and render-node extraction.
export 'src/worker/parse_worker_stub.dart'
    if (dart.library.ffi) 'src/worker/parse_worker.dart';

/// Flutter markdown rendering widgets with streaming token animation support.
export 'src/render/view.dart';

/// Tree-sitter markdown parser API returning full syntax trees.
export 'src/parser/tree_sitter_markdown_parser_stub.dart'
    if (dart.library.ffi) 'src/parser/tree_sitter_markdown_parser.dart';

/// Native tree-sitter language pointer helpers.
///
/// On non-FFI platforms (for example web), these APIs throw
/// [UnsupportedError].
export 'src/native/languages_stub.dart'
    if (dart.library.ffi) 'src/native/languages_ffi.dart';
