abstract class MarkdownBlockNode {
  const MarkdownBlockNode({required this.start, required this.end});

  final int start;
  final int end;
}

class MarkdownDocument {
  const MarkdownDocument({required this.blocks, required this.length});

  final List<MarkdownBlockNode> blocks;
  final int length;
}

class HeadingNode extends MarkdownBlockNode {
  const HeadingNode({
    required super.start,
    required super.end,
    required this.level,
    required this.text,
  });

  final int level;
  final String text;
}

class ParagraphNode extends MarkdownBlockNode {
  const ParagraphNode({
    required super.start,
    required super.end,
    required this.text,
  });

  final String text;
}

class CodeFenceNode extends MarkdownBlockNode {
  const CodeFenceNode({
    required super.start,
    required super.end,
    required this.fence,
    required this.language,
    required this.code,
    required this.closed,
  });

  final String fence;
  final String language;
  final String code;
  final bool closed;
}

class ListNode extends MarkdownBlockNode {
  const ListNode({
    required super.start,
    required super.end,
    required this.ordered,
    required this.items,
  });

  final bool ordered;
  final List<ListItemNode> items;
}

class ListItemNode {
  const ListItemNode({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}
