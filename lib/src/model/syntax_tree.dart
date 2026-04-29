import 'dart:convert';

/// Immutable tree-sitter syntax node.
///
/// This model is returned by [TreeSitterMarkdownParser] when callers need the
/// full markdown syntax tree instead of normalized render blocks. Byte offsets
/// use UTF-8 offsets from the original markdown source.
class MarkdownSyntaxNode {
  /// Creates a syntax node with source range, optional source [text], and
  /// nested [children].
  const MarkdownSyntaxNode({
    required this.type,
    required this.startByte,
    required this.endByte,
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
    required this.children,
    this.text,
  });

  /// Tree-sitter node type, for example `document`, `paragraph`, or
  /// `fenced_code_block`.
  final String type;

  /// Inclusive UTF-8 byte offset where this node starts.
  final int startByte;

  /// Exclusive UTF-8 byte offset where this node ends.
  final int endByte;

  /// Zero-based source row where this node starts.
  final int startRow;

  /// Zero-based source column where this node starts.
  final int startColumn;

  /// Zero-based source row where this node ends.
  final int endRow;

  /// Zero-based source column where this node ends.
  final int endColumn;

  /// Source text captured for this node, when available.
  final String? text;

  /// Child syntax nodes in source order.
  final List<MarkdownSyntaxNode> children;

  /// Whether this node has no children.
  bool get isLeaf => children.isEmpty;

  /// Converts this node and all descendants to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      'startByte': startByte,
      'endByte': endByte,
      'startRow': startRow,
      'startColumn': startColumn,
      'endRow': endRow,
      'endColumn': endColumn,
      'text': text,
      'children':
          children.map((MarkdownSyntaxNode node) => node.toJson()).toList(),
    };
  }

  /// Decodes a [MarkdownSyntaxNode] from a JSON-compatible object.
  static MarkdownSyntaxNode fromJsonObject(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid syntax tree JSON object');
    }

    final Object? rawChildren = value['children'];
    if (rawChildren is! List<dynamic>) {
      throw const FormatException('Invalid syntax tree JSON children');
    }

    return MarkdownSyntaxNode(
      type: value['type'] as String,
      startByte: (value['startByte'] as num).toInt(),
      endByte: (value['endByte'] as num).toInt(),
      startRow: (value['startRow'] as num).toInt(),
      startColumn: (value['startColumn'] as num).toInt(),
      endRow: (value['endRow'] as num).toInt(),
      endColumn: (value['endColumn'] as num).toInt(),
      text: value['text'] as String?,
      children: rawChildren.map(MarkdownSyntaxNode.fromJsonObject).toList(),
    );
  }

  /// Decodes a [MarkdownSyntaxNode] from a JSON string.
  static MarkdownSyntaxNode fromJsonString(String json) {
    return fromJsonObject(jsonDecode(json));
  }
}
