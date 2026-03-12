import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'markdown_syntax_tree.dart';
import 'native_symbols.dart';
import 'rope_string.dart';

/// Native tree-sitter markdown parser facade.
///
/// Produces full [MarkdownSyntaxNode] trees for block or inline grammars.
final class TreeSitterMarkdownParser {
  const TreeSitterMarkdownParser();

  /// Parses markdown using the block grammar.
  MarkdownSyntaxNode parseBlocks(String markdown) {
    return _parse(markdown, _parseBlocksToJson);
  }

  /// Parses markdown from [rope] using the block grammar.
  MarkdownSyntaxNode parseBlocksFromRope(RopeString rope) {
    return parseBlocks(rope.toString());
  }

  /// Parses markdown using the inline grammar.
  MarkdownSyntaxNode parseInlines(String markdown) {
    return _parse(markdown, _parseInlinesToJson);
  }

  /// Parses markdown from [rope] using the inline grammar.
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

final _DartParseJson _parseBlocksToJson = streamingMarkdownDylib
    .lookupFunction<_NativeParseJson, _DartParseJson>(
      'streaming_markdown_parse_blocks_to_json',
    );

final _DartParseJson _parseInlinesToJson = streamingMarkdownDylib
    .lookupFunction<_NativeParseJson, _DartParseJson>(
      'streaming_markdown_parse_inlines_to_json',
    );

final void Function(Pointer<Utf8>) _freeCString = streamingMarkdownDylib
    .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
      'streaming_markdown_rope_free_c_string',
    );
