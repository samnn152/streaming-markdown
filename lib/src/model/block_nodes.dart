/// Base type for parsed block-level Markdown nodes.
abstract class MarkdownBlockNode {
  /// Creates a block node with byte range `[start, end)`.
  const MarkdownBlockNode({required this.start, required this.end});

  /// Inclusive start byte offset of the node in source text.
  final int start;

  /// Exclusive end byte offset of the node in source text.
  final int end;
}

/// Immutable parse result for a full markdown document.
class MarkdownDocument {
  /// Creates a parsed document with [blocks] and full source [length].
  const MarkdownDocument({required this.blocks, required this.length});

  /// Top-level block nodes in source order.
  final List<MarkdownBlockNode> blocks;

  /// Total source length (in UTF-16 code units) used by the parser input.
  final int length;
}

/// ATX (`#`) or Setext (`===`/`---`) heading node.
class HeadingNode extends MarkdownBlockNode {
  /// Creates a heading node.
  const HeadingNode({
    required super.start,
    required super.end,
    required this.level,
    required this.text,
  });

  /// Heading level from `1` to `6`.
  final int level;

  /// Heading content with marker tokens removed.
  final String text;
}

/// Paragraph block node.
class ParagraphNode extends MarkdownBlockNode {
  /// Creates a paragraph node.
  const ParagraphNode({
    required super.start,
    required super.end,
    required this.text,
  });

  /// Paragraph text content.
  final String text;
}

/// Fenced code block node (triple backticks or tildes).
class CodeFenceNode extends MarkdownBlockNode {
  /// Creates a fenced code block node.
  const CodeFenceNode({
    required super.start,
    required super.end,
    required this.fence,
    required this.language,
    required this.code,
    required this.closed,
  });

  /// Fence marker text used to open the block (for example ```).
  final String fence;

  /// Parsed language identifier after opening fence, if any.
  final String language;

  /// Raw code content inside the fence.
  final String code;

  /// Whether a matching closing fence was present.
  final bool closed;
}

/// Ordered (`1.`) or unordered (`-`) list block node.
class ListNode extends MarkdownBlockNode {
  /// Creates a list node.
  const ListNode({
    required super.start,
    required super.end,
    required this.ordered,
    required this.items,
  });

  /// Whether this list is ordered.
  final bool ordered;

  /// Flattened list item nodes for this list block.
  final List<ListItemNode> items;
}

/// Single list item node.
class ListItemNode {
  /// Creates a list item node.
  const ListItemNode({
    required this.start,
    required this.end,
    required this.text,
  });

  /// Inclusive start byte offset of this item in source text.
  final int start;

  /// Exclusive end byte offset of this item in source text.
  final int end;

  /// Text content of the list item.
  final String text;
}
