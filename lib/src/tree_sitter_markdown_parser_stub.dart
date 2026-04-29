import 'markdown_syntax_tree.dart';
import 'rope_string.dart';

/// Native tree-sitter markdown parser facade.
///
/// This API is unavailable on non-FFI platforms (for example web).
class TreeSitterMarkdownParser {
  /// Creates a tree-sitter Markdown parser facade.
  ///
  /// The parser is unavailable on non-FFI platforms, so parse methods throw
  /// [UnsupportedError].
  const TreeSitterMarkdownParser();

  /// Parses [markdown] using the tree-sitter Markdown block grammar.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  MarkdownSyntaxNode parseBlocks(String markdown) {
    throw UnsupportedError(
      'TreeSitterMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// Parses markdown from [rope] using the tree-sitter Markdown block grammar.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  MarkdownSyntaxNode parseBlocksFromRope(RopeString rope) {
    return parseBlocks(rope.toString());
  }

  /// Parses [markdown] using the tree-sitter Markdown inline grammar.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  MarkdownSyntaxNode parseInlines(String markdown) {
    throw UnsupportedError(
      'TreeSitterMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  /// Parses markdown from [rope] using the tree-sitter Markdown inline grammar.
  ///
  /// Throws [UnsupportedError] on non-FFI platforms.
  MarkdownSyntaxNode parseInlinesFromRope(RopeString rope) {
    return parseInlines(rope.toString());
  }
}
