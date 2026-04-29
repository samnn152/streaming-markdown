/// Normalized markdown block passed from the parser to the renderer.
///
/// A render node keeps both the original source slice ([raw]) and parser
/// metadata such as source byte offsets and row numbers. Most applications do
/// not create these manually; use [StreamingMarkdownParseWorker] and render the
/// returned `result.blocks` with `AnimatedStreamingMarkdown`.
class MarkdownRenderNode {
  /// Creates an immutable render node.
  const MarkdownRenderNode({
    required this.type,
    required this.depth,
    required this.startByte,
    required this.endByte,
    required this.startRow,
    required this.endRow,
    required this.raw,
    required this.content,
  });

  /// Creates a render node from a JSON-like map returned by the native parser.
  factory MarkdownRenderNode.fromDynamicMap(Map<dynamic, dynamic> map) {
    int readInt(String key) {
      final Object? value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    return MarkdownRenderNode(
      type: (map['type'] as String?) ?? 'unknown',
      depth: readInt('depth'),
      startByte: readInt('startByte'),
      endByte: readInt('endByte'),
      startRow: readInt('startRow'),
      endRow: readInt('endRow'),
      raw: (map['raw'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
    );
  }

  /// Tree-sitter or normalized block type, for example `paragraph`,
  /// `atx_heading`, `fenced_code_block`, or `pipe_table`.
  final String type;

  /// Nesting depth in the source syntax tree.
  final int depth;

  /// Inclusive UTF-8 byte offset where this block starts in the source.
  final int startByte;

  /// Exclusive UTF-8 byte offset where this block ends in the source.
  final int endByte;

  /// Zero-based source row where this block starts.
  final int startRow;

  /// Zero-based source row where this block ends.
  final int endRow;

  /// Original markdown source slice for this block.
  final String raw;

  /// Human-readable content extracted from [raw] when available.
  final String content;
}

/// Preferred public name for a block ready to render.
///
/// [MarkdownRenderNode] remains available for compatibility with `0.2.x`, but
/// new APIs and documentation use [MarkdownBlock] because the value represents
/// a normalized block of markdown content.
typedef MarkdownBlock = MarkdownRenderNode;
