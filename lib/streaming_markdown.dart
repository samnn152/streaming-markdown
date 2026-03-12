import 'dart:ffi';

import 'src/native_symbols.dart';

export 'src/native_rope_buffer.dart';
export 'src/native_symbols.dart'
    show
        isStreamingMarkdownNativeLibraryAvailable,
        streamingMarkdownLibraryName;
export 'src/markdown_nodes.dart';
export 'src/markdown_syntax_tree.dart';
export 'src/markdown_render_node.dart';
export 'src/native_incremental_markdown_parser.dart';
export 'src/rope_markdown_parser.dart';
export 'src/rope_string.dart';
export 'src/streaming_markdown_parse_worker.dart';
export 'src/streaming_markdown_render_view.dart';
export 'src/tree_sitter_markdown_parser.dart';

/// Returns a pointer to the tree-sitter Markdown [TSLanguage].
///
/// This pointer can be passed into a tree-sitter parser created via another
/// Dart FFI wrapper for libtree-sitter.
Pointer<Void> markdownLanguage() => getMarkdownLanguageNative();

/// Returns a pointer to the tree-sitter Markdown inline [TSLanguage].
Pointer<Void> markdownInlineLanguage() => getMarkdownInlineLanguageNative();
