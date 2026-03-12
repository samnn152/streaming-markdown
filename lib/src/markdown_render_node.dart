class MarkdownRenderNode {
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

  final String type;
  final int depth;
  final int startByte;
  final int endByte;
  final int startRow;
  final int endRow;
  final String raw;
  final String content;
}
