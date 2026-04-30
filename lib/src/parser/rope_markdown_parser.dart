import '../model/block_nodes.dart';
import '../model/rope.dart';

part 'rope_markdown_models.dart';

/// Small pure-Dart block parser for [RopeString] sources.
///
/// This parser is intentionally lightweight. It is useful for environments
/// where the native tree-sitter parser is unavailable and for tests that only
/// need basic block structure.
class RopeMarkdownParser {
  /// Creates a pure-Dart rope markdown parser.
  const RopeMarkdownParser();

  /// Parses [source] into a [MarkdownDocument].
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

      if (i == 0 && _isFrontMatterStart(line.text)) {
        final _GenericBlockResult frontMatter = _parseFrontMatter(lines, i);
        if (frontMatter.closed) {
          blocks.add(
            GenericBlockNode(
              start: line.start,
              end: frontMatter.end,
              type: 'front_matter',
              content: frontMatter.content,
            ),
          );
          i = frontMatter.nextIndex;
          continue;
        }
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

      final _SetextHeadingMatch? setext = _parseSetextHeading(lines, i);
      if (setext != null) {
        blocks.add(
          HeadingNode(
            start: line.start,
            end: setext.end,
            level: setext.level,
            text: setext.text,
            type: 'setext_heading',
          ),
        );
        i = setext.nextIndex;
        continue;
      }

      if (_isThematicBreak(line.text)) {
        blocks.add(
          GenericBlockNode(
            start: line.start,
            end: line.end,
            type: 'thematic_break',
            content: '',
          ),
        );
        i++;
        continue;
      }

      final _GenericBlockResult? table = _parsePipeTable(lines, i);
      if (table != null) {
        blocks.add(
          GenericBlockNode(
            start: line.start,
            end: table.end,
            type: 'pipe_table',
            content: table.content,
          ),
        );
        i = table.nextIndex;
        continue;
      }

      if (_isBlockQuoteStart(line.text)) {
        final _GenericBlockResult quote = _parseBlockQuote(lines, i);
        blocks.add(
          GenericBlockNode(
            start: line.start,
            end: quote.end,
            type: 'block_quote',
            content: quote.content,
          ),
        );
        i = quote.nextIndex;
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

      final String? referenceType = _referenceDefinitionType(line.text);
      if (referenceType != null) {
        blocks.add(
          GenericBlockNode(
            start: line.start,
            end: line.end,
            type: referenceType,
            content: _referenceDefinitionContent(referenceType, line.text),
          ),
        );
        i++;
        continue;
      }

      if (_isHtmlBlockStart(line.text)) {
        final _GenericBlockResult html = _parseHtmlBlock(lines, i);
        blocks.add(
          GenericBlockNode(
            start: line.start,
            end: html.end,
            type: 'html_block',
            content: html.content,
          ),
        );
        i = html.nextIndex;
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

  _SetextHeadingMatch? _parseSetextHeading(
    List<_LineSlice> lines,
    int startIndex,
  ) {
    if (startIndex + 1 >= lines.length) {
      return null;
    }
    final _LineSlice textLine = lines[startIndex];
    final _LineSlice markerLine = lines[startIndex + 1];
    if (_isBlank(textLine.text) || !_isSetextDelimiter(markerLine.text)) {
      return null;
    }
    if (_startsBlock(textLine.text, allowSetext: false)) {
      return null;
    }
    final String marker = markerLine.text.trimLeft();
    return _SetextHeadingMatch(
      end: markerLine.end,
      nextIndex: startIndex + 2,
      level: marker.startsWith('=') ? 1 : 2,
      text: textLine.text.trim(),
    );
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
      if (i != startIndex && _startsBlock(line.text)) break;
      if (i == startIndex + 1 && _isSetextDelimiter(line.text)) break;

      if (text.isNotEmpty) {
        text.writeln();
      }
      text.write(line.text);
      i++;
    }

    final int end = i == startIndex ? lines[startIndex].end : lines[i - 1].end;
    return _ParagraphResult(end: end, nextIndex: i, text: text.toString());
  }

  _GenericBlockResult _parseFrontMatter(
    List<_LineSlice> lines,
    int startIndex,
  ) {
    final StringBuffer content = StringBuffer();
    for (int i = startIndex + 1; i < lines.length; i++) {
      if (_isFrontMatterStart(lines[i].text)) {
        return _GenericBlockResult(
          end: lines[i].end,
          nextIndex: i + 1,
          content: content.toString().trimRight(),
          closed: true,
        );
      }
      content.writeln(lines[i].text);
    }
    return _GenericBlockResult(
      end: lines[startIndex].end,
      nextIndex: startIndex + 1,
      content: '',
      closed: false,
    );
  }

  _GenericBlockResult? _parsePipeTable(
    List<_LineSlice> lines,
    int startIndex,
  ) {
    if (startIndex + 1 >= lines.length ||
        !_isPipeTableRow(lines[startIndex].text) ||
        !_isPipeTableDelimiter(lines[startIndex + 1].text)) {
      return null;
    }

    final StringBuffer raw = StringBuffer()..writeln(lines[startIndex].text);
    raw.writeln(lines[startIndex + 1].text);
    int i = startIndex + 2;
    while (i < lines.length && _isPipeTableRow(lines[i].text)) {
      raw.writeln(lines[i].text);
      i++;
    }

    return _GenericBlockResult(
      end: lines[i - 1].end,
      nextIndex: i,
      content: raw.toString().trimRight(),
      closed: true,
    );
  }

  _GenericBlockResult _parseBlockQuote(
    List<_LineSlice> lines,
    int startIndex,
  ) {
    final StringBuffer content = StringBuffer();
    int i = startIndex;
    while (i < lines.length) {
      final String text = lines[i].text;
      if (!_isBlockQuoteStart(text)) {
        break;
      }
      content.writeln(text.replaceFirst(RegExp(r'^\s{0,3}>\s?'), ''));
      i++;
    }
    return _GenericBlockResult(
      end: lines[i - 1].end,
      nextIndex: i,
      content: content.toString().trimRight(),
      closed: true,
    );
  }

  _GenericBlockResult _parseHtmlBlock(List<_LineSlice> lines, int startIndex) {
    final StringBuffer content = StringBuffer();
    int i = startIndex;
    while (i < lines.length && !_isBlank(lines[i].text)) {
      content.writeln(lines[i].text);
      i++;
    }
    return _GenericBlockResult(
      end: lines[i - 1].end,
      nextIndex: i,
      content: content.toString().trimRight(),
      closed: true,
    );
  }

  bool _startsBlock(String text, {bool allowSetext = true}) {
    return _parseHeading(_LineSlice(start: 0, end: text.length, text: text)) !=
            null ||
        _parseFenceStart(text) != null ||
        _parseListItem(text) != null ||
        _isThematicBreak(text) ||
        _isBlockQuoteStart(text) ||
        _isHtmlBlockStart(text) ||
        _referenceDefinitionType(text) != null ||
        (allowSetext && _isSetextDelimiter(text));
  }

  bool _isFrontMatterStart(String text) {
    return RegExp(r'^\s{0,3}---\s*$').hasMatch(text);
  }

  bool _isThematicBreak(String text) {
    final String compact = text.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 3) {
      return false;
    }
    return RegExp(r'^(\*\*\*+|---+|___+)$').hasMatch(compact);
  }

  bool _isSetextDelimiter(String text) {
    return RegExp(r'^\s{0,3}(=+|-+)\s*$').hasMatch(text);
  }

  bool _isPipeTableRow(String text) {
    return text.contains('|') && text.trim().split('|').length >= 3;
  }

  bool _isPipeTableDelimiter(String text) {
    final String trimmed = text.trim();
    if (!trimmed.contains('|')) {
      return false;
    }
    final List<String> cells = trimmed
        .split('|')
        .map((String cell) => cell.trim())
        .where((String cell) => cell.isNotEmpty)
        .toList(growable: false);
    if (cells.isEmpty) {
      return false;
    }
    return cells.every(
      (String cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell),
    );
  }

  bool _isBlockQuoteStart(String text) {
    return RegExp(r'^\s{0,3}>').hasMatch(text);
  }

  bool _isHtmlBlockStart(String text) {
    final String trimmed = text.trimLeft();
    return RegExp(
      r'^</?(?:article|aside|blockquote|details|div|dl|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|main|nav|ol|p|pre|section|table|ul|script|style|!--)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  String? _referenceDefinitionType(String text) {
    if (RegExp(r'^\s{0,3}\[\^[^\]]+\]:').hasMatch(text)) {
      return 'footnote_definition';
    }
    if (RegExp(r'^\s{0,3}\[[^\]]+\]:\s*\S+').hasMatch(text)) {
      return 'link_reference_definition';
    }
    return null;
  }

  String _referenceDefinitionContent(String type, String text) {
    if (type == 'footnote_definition') {
      return text.replaceFirst(RegExp(r'^\s{0,3}\[\^[^\]]+\]:\s*'), '').trim();
    }
    if (type == 'link_reference_definition') {
      return text.replaceFirst(RegExp(r'^\s{0,3}\[[^\]]+\]:\s*'), '').trim();
    }
    return text.trim();
  }

  bool _isBlank(String text) => text.trim().isEmpty;
}

/// Convenience parser that owns a mutable [RopeString] buffer.
///
/// Use this when you want a pure-Dart append-and-parse loop without the
/// isolate-backed [StreamingMarkdownParseWorker].
class StreamingMarkdownParser {
  /// Creates a streaming parser backed by [parser].
  StreamingMarkdownParser({RopeMarkdownParser? parser})
      : _parser = parser ?? const RopeMarkdownParser();

  final RopeString _buffer = RopeString();
  final RopeMarkdownParser _parser;

  /// Current mutable source buffer.
  RopeString get buffer => _buffer;

  /// Parses the current [buffer].
  MarkdownDocument parse() => _parser.parse(_buffer);

  /// Appends [chunk] to [buffer] and parses the full buffer.
  MarkdownDocument appendAndParse(String chunk) {
    _buffer.append(chunk);
    return parse();
  }

  /// Clears the current [buffer].
  void clear() => _buffer.clear();
}
