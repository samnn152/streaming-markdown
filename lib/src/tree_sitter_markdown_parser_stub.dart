import 'markdown_syntax_tree.dart';
import 'rope_string.dart';

/// Native tree-sitter markdown parser facade.
///
/// This API is unavailable on non-FFI platforms (for example web).
class TreeSitterMarkdownParser {
  const TreeSitterMarkdownParser();

  MarkdownSyntaxNode parseBlocks(String markdown) {
    throw UnsupportedError(
      'TreeSitterMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  MarkdownSyntaxNode parseBlocksFromRope(RopeString rope) {
    return parseBlocks(rope.toString());
  }

  MarkdownSyntaxNode parseInlines(String markdown) {
    throw UnsupportedError(
      'TreeSitterMarkdownParser is only available on FFI-enabled platforms.',
    );
  }

  MarkdownSyntaxNode parseInlinesFromRope(RopeString rope) {
    return parseInlines(rope.toString());
  }
}
