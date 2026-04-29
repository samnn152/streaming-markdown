import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../model/syntax_tree.dart';
import '../native/symbols.dart';
import '../model/rope.dart';

/// Native tree-sitter markdown parser facade.
///
/// Produces full [MarkdownSyntaxNode] trees for block or inline grammars.
class TreeSitterMarkdownParser {
  /// Creates a tree-sitter Markdown parser facade.
  ///
  /// The underlying native parser is loaded lazily from the package dynamic
  /// library when a parse method is called.
  const TreeSitterMarkdownParser();

  /// Parses [markdown] using the tree-sitter Markdown block grammar.
  ///
  /// Use this when you need source ranges and syntax-node types instead of
  /// normalized render blocks.
  MarkdownSyntaxNode parseBlocks(String markdown) {
    return _parse(markdown, _parseBlocksToJson);
  }

  /// Parses markdown from [rope] using the tree-sitter Markdown block grammar.
  MarkdownSyntaxNode parseBlocksFromRope(RopeString rope) {
    return parseBlocks(rope.toString());
  }

  /// Parses [markdown] using the tree-sitter Markdown inline grammar.
  ///
  /// This is mainly useful for diagnostics and parser tooling. Most rendering
  /// use cases should parse complete block documents instead.
  MarkdownSyntaxNode parseInlines(String markdown) {
    return _parse(markdown, _parseInlinesToJson);
  }

  /// Parses markdown from [rope] using the tree-sitter Markdown inline grammar.
  MarkdownSyntaxNode parseInlinesFromRope(RopeString rope) {
    return parseInlines(rope.toString());
  }

  MarkdownSyntaxNode _parse(
    String markdown,
    Pointer<Utf8> Function(Pointer<Utf8>) parseFn,
  ) {
    final Pointer<Utf8> nativeInput = markdown.toNativeUtf8();
    try {
      final Pointer<Utf8> nativeJson = parseFn(nativeInput);
      if (nativeJson == nullptr) {
        throw StateError('Native tree-sitter parse failed');
      }

      try {
        return MarkdownSyntaxNode.fromJsonString(nativeJson.toDartString());
      } finally {
        _freeCString(nativeJson);
      }
    } finally {
      malloc.free(nativeInput);
    }
  }
}

typedef _NativeParseJson = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _DartParseJson = Pointer<Utf8> Function(Pointer<Utf8>);

final _DartParseJson _parseBlocksToJson =
    streamingMarkdownDylib.lookupFunction<_NativeParseJson, _DartParseJson>(
  'streaming_markdown_parse_blocks_to_json',
);

final _DartParseJson _parseInlinesToJson =
    streamingMarkdownDylib.lookupFunction<_NativeParseJson, _DartParseJson>(
  'streaming_markdown_parse_inlines_to_json',
);

final void Function(Pointer<Utf8>) _freeCString = streamingMarkdownDylib
    .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
  'streaming_markdown_rope_free_c_string',
);
