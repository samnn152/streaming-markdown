part of 'rope_markdown_parser.dart';

class _LineSlice {
  const _LineSlice({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

class _HeadingMatch {
  const _HeadingMatch({required this.level, required this.text});

  final int level;
  final String text;
}

class _FenceStart {
  const _FenceStart({
    required this.fence,
    required this.marker,
    required this.width,
    required this.language,
  });

  final String fence;
  final String marker;
  final int width;
  final String language;
}

class _FenceResult {
  const _FenceResult({
    required this.end,
    required this.nextIndex,
    required this.code,
    required this.closed,
  });

  final int end;
  final int nextIndex;
  final String code;
  final bool closed;
}

class _ListItemMatch {
  const _ListItemMatch({required this.ordered, required this.text});

  final bool ordered;
  final String text;
}

class _ListResult {
  const _ListResult({
    required this.end,
    required this.nextIndex,
    required this.items,
  });

  final int end;
  final int nextIndex;
  final List<ListItemNode> items;
}

class _ParagraphResult {
  const _ParagraphResult({
    required this.end,
    required this.nextIndex,
    required this.text,
  });

  final int end;
  final int nextIndex;
  final String text;
}
