import 'markdown_nodes.dart';
import 'rope_string.dart';

final class RopeMarkdownParser {
  const RopeMarkdownParser();

  MarkdownDocument parse(RopeString source) {
    final List<_LineSlice> lines = _readLines(source);
    final List<MarkdownBlockNode> blocks = <MarkdownBlockNode>[];

    int i = 0;
    while (i < lines.length) {
      final _LineSlice line = lines[i];
      if (_isBlank(line.text)) {
        i++;
        continue;
      }

      final _HeadingMatch? heading = _parseHeading(line);
      if (heading != null) {
        blocks.add(
          HeadingNode(
            start: line.start,
            end: line.end,
            level: heading.level,
            text: heading.text,
          ),
        );
        i++;
        continue;
      }

      final _FenceStart? fenceStart = _parseFenceStart(line.text);
      if (fenceStart != null) {
        final _FenceResult fenced = _parseFence(lines, i, fenceStart);
        blocks.add(
          CodeFenceNode(
            start: lines[i].start,
            end: fenced.end,
            fence: fenceStart.fence,
            language: fenceStart.language,
            code: fenced.code,
            closed: fenced.closed,
          ),
        );
        i = fenced.nextIndex;
        continue;
      }

      final _ListItemMatch? listItem = _parseListItem(line.text);
      if (listItem != null) {
        final _ListResult listResult = _parseList(lines, i, listItem.ordered);
        blocks.add(
          ListNode(
            start: lines[i].start,
            end: listResult.end,
            ordered: listItem.ordered,
            items: listResult.items,
          ),
        );
        i = listResult.nextIndex;
        continue;
      }

      final _ParagraphResult paragraph = _parseParagraph(lines, i);
      blocks.add(
        ParagraphNode(
          start: lines[i].start,
          end: paragraph.end,
          text: paragraph.text,
        ),
      );
      i = paragraph.nextIndex;
    }

    return MarkdownDocument(blocks: blocks, length: source.length);
  }

  List<_LineSlice> _readLines(RopeString source) {
    final List<_LineSlice> lines = <_LineSlice>[];
    final int length = source.length;
    int start = 0;

    for (int i = 0; i < length; i++) {
      if (source.codeUnitAt(i) == 10) {
        int contentEnd = i;
        if (contentEnd > start && source.codeUnitAt(contentEnd - 1) == 13) {
          contentEnd--;
        }
        lines.add(
          _LineSlice(
            start: start,
            end: i + 1,
            text: source.substring(start, contentEnd),
          ),
        );
        start = i + 1;
      }
    }

    if (start < length || length == 0) {
      lines.add(
        _LineSlice(start: start, end: length, text: source.substring(start)),
      );
    }

    return lines;
  }

  _HeadingMatch? _parseHeading(_LineSlice line) {
    int i = 0;
    while (i < line.text.length && line.text.codeUnitAt(i) == 32) {
      i++;
    }

    int level = 0;
    while (i < line.text.length && line.text.codeUnitAt(i) == 35 && level < 6) {
      level++;
      i++;
    }

    if (level == 0) return null;
    if (i >= line.text.length || line.text.codeUnitAt(i) != 32) return null;

    final String text = line.text.substring(i + 1).trimRight();
    return _HeadingMatch(level: level, text: text);
  }

  _FenceStart? _parseFenceStart(String text) {
    final String trimmed = text.trimLeft();
    if (trimmed.length < 3) return null;

    final String marker = trimmed[0];
    if (marker != '`' && marker != '~') return null;

    int i = 0;
    while (i < trimmed.length && trimmed[i] == marker) {
      i++;
    }
    if (i < 3) return null;

    final String language = trimmed.substring(i).trim();
    return _FenceStart(
      fence: marker * i,
      marker: marker,
      width: i,
      language: language,
    );
  }

  _FenceResult _parseFence(
    List<_LineSlice> lines,
    int startIndex,
    _FenceStart start,
  ) {
    final StringBuffer code = StringBuffer();

    for (int i = startIndex + 1; i < lines.length; i++) {
      final String trimmed = lines[i].text.trimLeft();
      if (_isFenceClose(trimmed, start.marker, start.width)) {
        return _FenceResult(
          end: lines[i].end,
          nextIndex: i + 1,
          code: code.toString(),
          closed: true,
        );
      }

      code.writeln(lines[i].text);
    }

    return _FenceResult(
      end: lines.last.end,
      nextIndex: lines.length,
      code: code.toString(),
      closed: false,
    );
  }

  bool _isFenceClose(String text, String marker, int width) {
    if (text.length < width) return false;
    for (int i = 0; i < width; i++) {
      if (text[i] != marker) return false;
    }
    for (int i = width; i < text.length; i++) {
      if (text[i] != marker && text.codeUnitAt(i) != 32) {
        return false;
      }
    }
    return true;
  }

  _ListItemMatch? _parseListItem(String text) {
    final RegExpMatch? unordered = RegExp(
      r'^\s*([-*+])\s+(.+)$',
    ).firstMatch(text);
    if (unordered != null) {
      return _ListItemMatch(ordered: false, text: unordered.group(2)!);
    }

    final RegExpMatch? ordered = RegExp(
      r'^\s*\d+[\.)]\s+(.+)$',
    ).firstMatch(text);
    if (ordered != null) {
      return _ListItemMatch(ordered: true, text: ordered.group(1)!);
    }

    return null;
  }

  _ListResult _parseList(List<_LineSlice> lines, int startIndex, bool ordered) {
    final List<ListItemNode> items = <ListItemNode>[];
    int i = startIndex;

    while (i < lines.length) {
      final _ListItemMatch? item = _parseListItem(lines[i].text);
      if (item == null || item.ordered != ordered) {
        break;
      }

      items.add(
        ListItemNode(start: lines[i].start, end: lines[i].end, text: item.text),
      );
      i++;
    }

    final int end = items.isEmpty ? lines[startIndex].end : items.last.end;
    return _ListResult(end: end, nextIndex: i, items: items);
  }

  _ParagraphResult _parseParagraph(List<_LineSlice> lines, int startIndex) {
    final StringBuffer text = StringBuffer();
    int i = startIndex;

    while (i < lines.length) {
      final _LineSlice line = lines[i];
      if (_isBlank(line.text)) break;
      if (_parseHeading(line) != null) break;
      if (_parseFenceStart(line.text) != null) break;
      if (_parseListItem(line.text) != null) break;

      if (text.isNotEmpty) {
        text.writeln();
      }
      text.write(line.text);
      i++;
    }

    final int end = i == startIndex ? lines[startIndex].end : lines[i - 1].end;
    return _ParagraphResult(end: end, nextIndex: i, text: text.toString());
  }

  bool _isBlank(String text) => text.trim().isEmpty;
}

final class StreamingMarkdownParser {
  StreamingMarkdownParser({RopeMarkdownParser? parser})
    : _parser = parser ?? const RopeMarkdownParser();

  final RopeString _buffer = RopeString();
  final RopeMarkdownParser _parser;

  RopeString get buffer => _buffer;

  MarkdownDocument parse() => _parser.parse(_buffer);

  MarkdownDocument appendAndParse(String chunk) {
    _buffer.append(chunk);
    return parse();
  }

  void clear() => _buffer.clear();
}

final class _LineSlice {
  const _LineSlice({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

final class _HeadingMatch {
  const _HeadingMatch({required this.level, required this.text});

  final int level;
  final String text;
}

final class _FenceStart {
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

final class _FenceResult {
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

final class _ListItemMatch {
  const _ListItemMatch({required this.ordered, required this.text});

  final bool ordered;
  final String text;
}

final class _ListResult {
  const _ListResult({
    required this.end,
    required this.nextIndex,
    required this.items,
  });

  final int end;
  final int nextIndex;
  final List<ListItemNode> items;
}

final class _ParagraphResult {
  const _ParagraphResult({
    required this.end,
    required this.nextIndex,
    required this.text,
  });

  final int end;
  final int nextIndex;
  final String text;
}
