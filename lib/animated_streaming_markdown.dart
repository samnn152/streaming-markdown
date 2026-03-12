/// Streaming Markdown public API.
///
/// Status:
/// - This package is currently vibe-coded.
/// - It is still under active construction and APIs may evolve quickly.
///
/// This entrypoint exports the main parsing, rendering, and incremental
/// streaming APIs.
///
/// Typical flow:
/// 1. Build or append text via [RopeString] or your own source stream.
/// 2. Parse incrementally via [StreamingMarkdownParseWorker] or
///    [NativeIncrementalMarkdownParser].
/// 3. Render [MarkdownRenderNode] blocks via [StreamingMarkdownRenderView].
library;

import 'dart:ffi';

import 'src/native_symbols.dart';

/// Native UTF-8 rope buffer implementation backed by C++.
export 'src/native_rope_buffer.dart';

/// Native library availability and resolved library name for current platform.
export 'src/native_symbols.dart'
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
export 'src/native_incremental_markdown_parser.dart';

/// Pure-Dart rope markdown parser.
export 'src/rope_markdown_parser.dart';

/// Append-friendly pure-Dart rope string.
export 'src/rope_string.dart';

/// Isolate worker wrapper for incremental parsing and render-node extraction.
export 'src/streaming_markdown_parse_worker.dart';

/// Flutter markdown rendering widget with streaming token animation support.
export 'src/streaming_markdown_render_view.dart';

/// Tree-sitter markdown parser API returning full syntax trees.
export 'src/tree_sitter_markdown_parser.dart';

/// Returns a pointer to the tree-sitter Markdown [TSLanguage].
///
/// This pointer can be passed into a tree-sitter parser created via another
/// Dart FFI wrapper for libtree-sitter.
Pointer<Void> markdownLanguage() => getMarkdownLanguageNative();

/// Returns a pointer to the tree-sitter Markdown inline [TSLanguage].
Pointer<Void> markdownInlineLanguage() => getMarkdownInlineLanguageNative();
