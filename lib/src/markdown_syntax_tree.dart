import 'dart:convert';

class MarkdownSyntaxNode {
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

  final String type;
  final int startByte;
  final int endByte;
  final int startRow;
  final int startColumn;
  final int endRow;
  final int endColumn;
  final String? text;
  final List<MarkdownSyntaxNode> children;

  bool get isLeaf => children.isEmpty;

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

  static MarkdownSyntaxNode fromJsonString(String json) {
    return fromJsonObject(jsonDecode(json));
  }
}
