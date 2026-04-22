part of 'streaming_markdown_render_view.dart';

mixin _StreamingMarkdownTextParsing {
  _ParsedList _parseListNode(MarkdownRenderNode node) {
    final List<String> lines = _normalizedRaw(node.raw).split('\n');
    final List<_ParsedListItem> items = <_ParsedListItem>[];

    for (final String line in lines) {
      final RegExpMatch? markerMatch = RegExp(
        r'^(\s*)([-+*]|\d+[.)])\s+(.*)$',
      ).firstMatch(line);
      if (markerMatch == null) {
        if (items.isNotEmpty && line.trim().isNotEmpty) {
          final _ParsedListItem last = items.removeLast();
          items.add(
            _ParsedListItem(
              level: last.level,
              ordered: last.ordered,
              order: last.order,
              taskState: last.taskState,
              text: '${last.text} ${line.trim()}',
              stableKey: last.stableKey,
            ),
          );
        }
        continue;
      }

      final String marker = markerMatch.group(2)!;
      String body = markerMatch.group(3)!.trimRight();
      bool? taskState;
      final RegExpMatch? taskMatch = RegExp(
        r'^\[([ xX])\]\s*(.*)$',
      ).firstMatch(body);
      if (taskMatch != null) {
        taskState = taskMatch.group(1)!.toLowerCase() == 'x';
        body = taskMatch.group(2)!;
      }

      final int level = (markerMatch.group(1)!.length / 2).floor();
      final bool ordered = RegExp(r'^\d').hasMatch(marker);
      final int order = ordered
          ? int.tryParse(marker.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1
          : 0;

      items.add(
        _ParsedListItem(
          level: level,
          ordered: ordered,
          order: order,
          taskState: taskState,
          text: body.trim(),
          stableKey: 'line_${items.length}',
        ),
      );
    }

    return _ParsedList(items: items);
  }

  _CalloutData? _parseCallout(String text) {
    final List<String> lines = text.split('\n');
    if (lines.isEmpty) {
      return null;
    }

    final RegExpMatch? match = RegExp(
      r'^\s*\[!(\w+)\]\s*(.*)$',
    ).firstMatch(lines.first);
    if (match == null) {
      return null;
    }

    final String kind = match.group(1)!.toLowerCase();
    final String title = match.group(2)!.trim().isEmpty
        ? kind[0].toUpperCase() + kind.substring(1)
        : match.group(2)!.trim();
    final String body = lines.skip(1).join('\n').trim();

    return _CalloutData(kind: kind, title: title, body: body);
  }

  Color _calloutColor(String? kind) {
    switch (kind) {
      case 'note':
        return const Color(0xFF58A6FF);
      case 'tip':
        return const Color(0xFF3FB950);
      case 'warning':
        return const Color(0xFFD29922);
      case 'important':
        return const Color(0xFFBC8CFF);
      case 'caution':
        return const Color(0xFFF85149);
      default:
        return const Color(0xFF8B949E);
    }
  }

  IconData _calloutIcon(String kind) {
    switch (kind) {
      case 'note':
        return Icons.info_outline;
      case 'tip':
        return Icons.lightbulb_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'important':
        return Icons.priority_high;
      case 'caution':
        return Icons.error_outline;
      default:
        return Icons.notes;
    }
  }

  String _quoteText(MarkdownRenderNode node) {
    return _normalizedRaw(node.raw)
        .split('\n')
        .map((String line) => line.replaceFirst(RegExp(r'^\s*>\s?'), ''))
        .join('\n')
        .trim();
  }

  String _codeText(MarkdownRenderNode node) {
    final String raw = _normalizedRaw(node.raw);
    if (node.type == 'fenced_code_block') {
      final List<String> lines = raw.split('\n');
      if (lines.isNotEmpty &&
          RegExp(r'^\s*(```+|~~~+)').hasMatch(lines.first)) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty &&
          RegExp(r'^\s*(```+|~~~+)\s*$').hasMatch(lines.last)) {
        lines.removeLast();
      }
      return lines.join('\n').trimRight();
    }
    return raw;
  }

  String _codeLanguage(String raw) {
    final RegExpMatch? match = RegExp(
      r'^\s*(```+|~~~+)\s*([A-Za-z0-9_+\-\.#]*)',
      multiLine: true,
    ).firstMatch(raw);
    if (match == null) {
      return '';
    }
    return match.group(2)!.trim();
  }

  _ParsedTable? _parseMarkdownTable(
    String raw, {
    bool allowLooseWithoutDelimiter = false,
    int minLooseRowsWithoutDelimiter = 1,
  }) {
    final List<String> lines = raw
        .split('\n')
        .map((String line) => line.trimRight())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2 && !allowLooseWithoutDelimiter) {
      return null;
    }

    int delimiterIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (_isTableDelimiterRow(lines[i])) {
        delimiterIndex = i;
        break;
      }
    }
    if (delimiterIndex < 0) {
      if (!allowLooseWithoutDelimiter) {
        return null;
      }

      final List<List<String>> rows = lines
          .map(_splitTableRow)
          .where((List<String> row) => row.isNotEmpty)
          .toList(growable: false);
      if (rows.length < minLooseRowsWithoutDelimiter || rows.isEmpty) {
        return null;
      }

      int width = 0;
      for (final List<String> row in rows) {
        if (row.length > width) {
          width = row.length;
        }
      }
      if (width <= 0) {
        return null;
      }

      final List<String> headers = _fitTableRowToWidth(rows.first, width);
      final List<List<String>> bodyRows = rows
          .skip(1)
          .map((List<String> row) => _fitTableRowToWidth(row, width))
          .toList(growable: false);

      return _ParsedTable(headers: headers, rows: bodyRows);
    }

    final List<String> rawHeaders = delimiterIndex > 0
        ? _splitTableRow(lines[delimiterIndex - 1])
        : <String>[];
    final List<String> delimiterCells = _splitTableRow(lines[delimiterIndex]);
    int width = rawHeaders.length > delimiterCells.length
        ? rawHeaders.length
        : delimiterCells.length;

    final List<List<String>> rawRows = <List<String>>[];
    for (int i = delimiterIndex + 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || !line.contains('|')) {
        continue;
      }

      final List<String> row = _splitTableRow(line);
      if (row.isEmpty) {
        continue;
      }
      rawRows.add(row);
      if (row.length > width) {
        width = row.length;
      }
    }

    if (width <= 0) {
      return null;
    }

    // Keep table stable during streaming even when header row is not ready yet.
    final List<String> headers = _fitTableRowToWidth(rawHeaders, width);
    final List<List<String>> rows = rawRows
        .map((List<String> row) => _fitTableRowToWidth(row, width))
        .toList(growable: false);

    return _ParsedTable(headers: headers, rows: rows);
  }

  List<String> _fitTableRowToWidth(List<String> row, int width) {
    final List<String> out = row.toList(growable: true);
    while (out.length < width) {
      out.add('');
    }
    if (out.length > width) {
      out.removeRange(width, out.length);
    }
    return out;
  }

  bool _isTableDelimiterRow(String line) {
    final List<String> cells = _splitTableRow(line);
    if (cells.isEmpty) {
      return false;
    }

    for (final String cell in cells) {
      final String normalized = cell.replaceAll(' ', '');
      if (!RegExp(r'^:?-+:?$').hasMatch(normalized)) {
        return false;
      }
    }
    return true;
  }

  List<String> _splitTableRow(String line) {
    final String value = line.trim();
    if (!value.contains('|')) {
      return <String>[];
    }

    final List<String> cells = <String>[];
    final StringBuffer current = StringBuffer();
    int codeFenceLength = 0;
    bool escaped = false;

    for (int i = 0; i < value.length; i++) {
      final String ch = value[i];

      if (escaped) {
        current.write(ch);
        escaped = false;
        continue;
      }

      if (ch == '\\') {
        escaped = true;
        current.write(ch);
        continue;
      }

      if (ch == '`') {
        int runLength = 1;
        while (i + runLength < value.length && value[i + runLength] == '`') {
          runLength += 1;
        }

        if (codeFenceLength == 0) {
          codeFenceLength = runLength;
        } else if (runLength >= codeFenceLength) {
          codeFenceLength = 0;
        }

        current.write(value.substring(i, i + runLength));
        i += runLength - 1;
        continue;
      }

      if (ch == '|' && codeFenceLength == 0) {
        cells.add(current.toString().trim());
        current.clear();
        continue;
      }

      current.write(ch);
    }
    cells.add(current.toString().trim());

    if (value.startsWith('|') && cells.isNotEmpty && cells.first.isEmpty) {
      cells.removeAt(0);
    }
    if (value.endsWith('|') && cells.isNotEmpty && cells.last.isEmpty) {
      cells.removeLast();
    }

    return cells
        .map((String cell) => cell.replaceAll(r'\|', '|'))
        .toList(growable: false);
  }

  Map<String, String> _extractLinkReferences(List<MarkdownRenderNode> nodes) {
    final Map<String, String> references = <String, String>{};
    for (final MarkdownRenderNode node in nodes) {
      if (node.type != 'link_reference_definition') {
        continue;
      }
      final String raw = _normalizedRaw(node.raw);
      for (final RegExpMatch match in RegExp(
        r'^\s*\[([^\]]+)\]:\s*(\S+)',
        multiLine: true,
      ).allMatches(raw)) {
        final String name = _normalizeReferenceKey(match.group(1)!);
        final String url = _stripEnclosingAngles(match.group(2)!);
        if (name.isNotEmpty && url.isNotEmpty) {
          references[name] = url;
        }
      }
    }
    return references;
  }

  Map<String, int> _extractFootnoteNumbers(List<MarkdownRenderNode> nodes) {
    final Map<String, int> numbers = <String, int>{};
    for (final MarkdownRenderNode node in nodes) {
      if (node.type != 'footnote_definition') {
        continue;
      }
      final RegExpMatch? match = RegExp(
        r'^\s*\[\^([^\]]+)\]:',
      ).firstMatch(_normalizedRaw(node.raw));
      if (match == null) {
        continue;
      }
      final String key = _normalizeFootnoteKey(match.group(1)!);
      if (key.isEmpty || numbers.containsKey(key)) {
        continue;
      }
      numbers[key] = numbers.length + 1;
    }
    return numbers;
  }

  List<_InlineToken> _parseInlineTokens(
    String text, {
    _InlineStyle style = const _InlineStyle(),
    Map<String, String> references = const <String, String>{},
    int depth = 0,
    bool allowUnclosedDelimiters = false,
  }) {
    if (text.isEmpty) {
      return <_InlineToken>[];
    }
    if (depth > 8) {
      return <_InlineToken>[_InlineToken.text(text: text, style: style)];
    }

    final List<_InlineToken> tokens = <_InlineToken>[];
    final StringBuffer plain = StringBuffer();

    void flushPlain() {
      if (plain.isEmpty) {
        return;
      }
      tokens.add(_InlineToken.text(text: plain.toString(), style: style));
      plain.clear();
    }

    int i = 0;
    while (i < text.length) {
      if (text.startsWith('![', i)) {
        final _InlineImageMatch? image = _matchInlineImageAt(text, i);
        if (image != null) {
          flushPlain();
          tokens.add(
            _InlineToken.image(altText: image.alt, imageUrl: image.url),
          );
          i = image.end;
          continue;
        }
      }

      if (text.codeUnitAt(i) == 91) {
        final _FootnoteReferenceMatch? footnoteRef = _matchFootnoteReferenceAt(
          text,
          i,
        );
        if (footnoteRef != null) {
          flushPlain();
          tokens.add(
            _InlineToken.footnote(footnoteReferenceId: footnoteRef.id),
          );
          i = footnoteRef.end;
          continue;
        }

        final _InlineLinkMatch? link = _matchInlineLinkAt(
          text,
          i,
          references: references,
        );
        if (link != null) {
          flushPlain();
          final List<_InlineToken> labelTokens = _parseInlineTokens(
            link.label,
            style: style,
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          );
          if (labelTokens.isEmpty) {
            tokens.add(
              _InlineToken.text(
                text: link.label,
                style: style,
                linkUrl: link.url,
              ),
            );
          } else {
            for (final _InlineToken token in labelTokens) {
              if (token.isImage) {
                tokens.add(token);
              } else {
                tokens.add(token.withLink(link.url));
              }
            }
          }
          i = link.end;
          continue;
        }
      }

      if (text.startsWith('<http://', i) || text.startsWith('<https://', i)) {
        final int end = text.indexOf('>', i + 1);
        if (end != -1) {
          flushPlain();
          final String url = text.substring(i + 1, end);
          tokens.add(_InlineToken.text(text: url, style: style, linkUrl: url));
          i = end + 1;
          continue;
        }
      }

      final _DelimitedMatch? code = _matchDelimited(text, i, '`');
      if (code != null) {
        flushPlain();
        tokens.add(
          _InlineToken.text(
            text: code.inner,
            style: style.copyWith(code: true),
          ),
        );
        i = code.end;
        continue;
      }

      final _DelimitedMatch? boldItalic = _matchAnyDelimited(
        text,
        i,
        const <String>['***', '___'],
        allowUnclosedDelimiters: allowUnclosedDelimiters,
      );
      if (boldItalic != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            boldItalic.inner,
            style: style.copyWith(bold: true, italic: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = boldItalic.end;
        continue;
      }

      final _DelimitedMatch? bold = _matchAnyDelimited(
          text,
          i,
          const <String>[
            '**',
            '__',
          ],
          allowUnclosedDelimiters: allowUnclosedDelimiters);
      if (bold != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            bold.inner,
            style: style.copyWith(bold: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = bold.end;
        continue;
      }

      final _DelimitedMatch? strike = _matchDelimited(text, i, '~~');
      if (strike != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            strike.inner,
            style: style.copyWith(strikethrough: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = strike.end;
        continue;
      }

      final _DelimitedMatch? italic = _matchAnyDelimited(
        text,
        i,
        const <String>['*', '_'],
        allowUnclosedDelimiters: allowUnclosedDelimiters,
      );
      if (italic != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            italic.inner,
            style: style.copyWith(italic: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = italic.end;
        continue;
      }

      plain.write(text[i]);
      i += 1;
    }

    flushPlain();
    return tokens;
  }

  _DelimitedMatch? _matchAnyDelimited(
    String text,
    int start,
    List<String> delimiters, {
    required bool allowUnclosedDelimiters,
  }) {
    for (final String delimiter in delimiters) {
      final _DelimitedMatch? match = _matchDelimited(
        text,
        start,
        delimiter,
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  _FootnoteReferenceMatch? _matchFootnoteReferenceAt(String text, int start) {
    final Match? match = RegExp(r'\[\^([^\]]+)\]').matchAsPrefix(text, start);
    if (match is! RegExpMatch) {
      return null;
    }
    return _FootnoteReferenceMatch(id: match.group(1)!, end: match.end);
  }

  _FootnoteDefinition? _parseFootnoteDefinition(String raw) {
    final List<String> lines = _normalizedRaw(raw).split('\n');
    if (lines.isEmpty) {
      return null;
    }

    final RegExpMatch? first = RegExp(
      r'^\s*\[\^([^\]]+)\]:\s*(.*)$',
    ).firstMatch(lines.first);
    if (first == null) {
      return null;
    }

    final String id = first.group(1)!.trim();
    final List<String> body = <String>[first.group(2)!.trim()];

    for (final String line in lines.skip(1)) {
      if (line.trim().isEmpty) {
        body.add('');
        continue;
      }
      body.add(line.replaceFirst(RegExp(r'^\s{0,4}'), '').trimRight());
    }

    return _FootnoteDefinition(id: id, body: body.join('\n').trim());
  }

  _DelimitedMatch? _matchDelimited(
    String text,
    int start,
    String delimiter, {
    bool allowUnclosedTail = false,
  }) {
    if (!text.startsWith(delimiter, start)) {
      return null;
    }
    final int endStart = text.indexOf(delimiter, start + delimiter.length);
    if (endStart == -1) {
      if (!allowUnclosedTail) {
        return null;
      }
      final String unclosedInner = text.substring(start + delimiter.length);
      if (unclosedInner.isEmpty) {
        return null;
      }
      return _DelimitedMatch(inner: unclosedInner, end: text.length);
    }
    final String inner = text.substring(start + delimiter.length, endStart);
    if (inner.isEmpty) {
      return null;
    }
    return _DelimitedMatch(inner: inner, end: endStart + delimiter.length);
  }

  _InlineImageMatch? _matchInlineImageAt(String text, int start) {
    if (!text.startsWith('![', start)) {
      return null;
    }
    final int closeBracket = text.indexOf(']', start + 2);
    if (closeBracket == -1 || closeBracket + 1 >= text.length) {
      return null;
    }

    if (text[closeBracket + 1] != '(') {
      return null;
    }
    final int closeParen = text.indexOf(')', closeBracket + 2);
    if (closeParen == -1) {
      return null;
    }

    final String alt = text.substring(start + 2, closeBracket).trim();
    final String rawUrl = text.substring(closeBracket + 2, closeParen).trim();
    if (rawUrl.isEmpty) {
      return null;
    }

    final String url = _stripEnclosingAngles(
      rawUrl.split(RegExp(r'\s+')).first,
    );
    return _InlineImageMatch(alt: alt, url: url, end: closeParen + 1);
  }

  _InlineImageMatch? _matchSingleInlineImage(String text) {
    final String trimmed = text.trim();
    final _InlineImageMatch? image = _matchInlineImageAt(trimmed, 0);
    if (image == null || image.end != trimmed.length) {
      return null;
    }
    return image;
  }

  _InlineLinkMatch? _matchInlineLinkAt(
    String text,
    int start, {
    required Map<String, String> references,
  }) {
    if (!text.startsWith('[', start)) {
      return null;
    }

    final int closeBracket = text.indexOf(']', start + 1);
    if (closeBracket == -1) {
      return null;
    }

    final String label = text.substring(start + 1, closeBracket);
    if (label.isEmpty) {
      return null;
    }

    if (closeBracket + 1 < text.length && text[closeBracket + 1] == '(') {
      final int closeParen = text.indexOf(')', closeBracket + 2);
      if (closeParen == -1) {
        return null;
      }

      final String raw = text.substring(closeBracket + 2, closeParen).trim();
      if (raw.isEmpty) {
        return null;
      }
      final String url = _stripEnclosingAngles(raw.split(RegExp(r'\s+')).first);
      return _InlineLinkMatch(label: label, url: url, end: closeParen + 1);
    }

    if (closeBracket + 1 < text.length && text[closeBracket + 1] == '[') {
      final int closeRef = text.indexOf(']', closeBracket + 2);
      if (closeRef == -1) {
        return null;
      }
      final String rawKey = text.substring(closeBracket + 2, closeRef).trim();
      final String key = _normalizeReferenceKey(
        rawKey.isEmpty ? label : rawKey,
      );
      final String? url = references[key];
      if (url == null) {
        return null;
      }
      return _InlineLinkMatch(label: label, url: url, end: closeRef + 1);
    }

    final String? shortcutUrl = references[_normalizeReferenceKey(label)];
    if (shortcutUrl != null) {
      return _InlineLinkMatch(
        label: label,
        url: shortcutUrl,
        end: closeBracket + 1,
      );
    }

    return null;
  }

  String _normalizeReferenceKey(String key) {
    return _normalizeFootnoteKey(key);
  }

  String _stripEnclosingAngles(String value) {
    final String trimmed = value.trim();
    if (trimmed.startsWith('<') &&
        trimmed.endsWith('>') &&
        trimmed.length > 2) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  String _contentOrRaw(MarkdownRenderNode node) {
    if (node.content.trim().isNotEmpty) {
      return node.content.trim();
    }
    return _normalizedRaw(node.raw).trim();
  }

  String _headingText(MarkdownRenderNode node) {
    if (node.content.trim().isNotEmpty) {
      return node.content.trim();
    }
    final String raw = _normalizedRaw(node.raw);
    return raw.replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '').trim();
  }

  int _headingLevelForNode(MarkdownRenderNode node) {
    if (node.type == 'atx_heading') {
      final RegExpMatch? match = RegExp(
        r'^\s{0,3}(#{1,6})\s',
      ).firstMatch(node.raw);
      if (match != null) {
        return match.group(1)!.length;
      }
      return 1;
    }

    if (node.type == 'setext_heading') {
      final List<String> lines = _normalizedRaw(node.raw).split('\n');
      if (lines.length >= 2 && RegExp(r'^\s*=+\s*$').hasMatch(lines[1])) {
        return 1;
      }
      return 2;
    }

    return 1;
  }

  String _paragraphText(MarkdownRenderNode node) {
    final String raw = _normalizedRaw(node.raw).trim();
    if (raw.isNotEmpty) {
      return raw;
    }
    return node.content.trim();
  }

  String _normalizedRaw(String raw) {
    return raw.replaceAll('\r', '').trimRight();
  }
}

class _ParsedList {
  const _ParsedList({required this.items});

  final List<_ParsedListItem> items;
}

class _ParsedListItem {
  const _ParsedListItem({
    required this.level,
    required this.ordered,
    required this.order,
    required this.taskState,
    required this.text,
    required this.stableKey,
  });

  final int level;
  final bool ordered;
  final int order;
  final bool? taskState;
  final String text;
  final String stableKey;
}

class _ParsedTable {
  const _ParsedTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

class _CalloutData {
  const _CalloutData({
    required this.kind,
    required this.title,
    required this.body,
  });

  final String kind;
  final String title;
  final String body;
}

class _DelimitedMatch {
  const _DelimitedMatch({required this.inner, required this.end});

  final String inner;
  final int end;
}

class _InlineImageMatch {
  const _InlineImageMatch({
    required this.alt,
    required this.url,
    required this.end,
  });

  final String alt;
  final String url;
  final int end;
}

class _InlineLinkMatch {
  const _InlineLinkMatch({
    required this.label,
    required this.url,
    required this.end,
  });

  final String label;
  final String url;
  final int end;
}

class _FootnoteReferenceMatch {
  const _FootnoteReferenceMatch({required this.id, required this.end});

  final String id;
  final int end;
}

class _FootnoteDefinition {
  const _FootnoteDefinition({required this.id, required this.body});

  final String id;
  final String body;
}

int? _footnoteNumberForId(Map<String, int> footnoteNumbers, String id) {
  return footnoteNumbers[_normalizeFootnoteKey(id)];
}

String _normalizeFootnoteKey(String key) {
  return key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
  });

  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? code,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      code: code ?? this.code,
    );
  }
}

class _InlineToken {
  const _InlineToken.text({
    required this.text,
    required this.style,
    this.linkUrl,
  })  : altText = '',
        imageUrl = null,
        footnoteReferenceId = null;

  const _InlineToken.image({required this.altText, required this.imageUrl})
      : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        footnoteReferenceId = null;

  const _InlineToken.footnote({required this.footnoteReferenceId})
      : text = '',
        style = const _InlineStyle(),
        linkUrl = null,
        altText = '',
        imageUrl = null;

  final String text;
  final _InlineStyle style;
  final String? linkUrl;
  final String altText;
  final String? imageUrl;
  final String? footnoteReferenceId;

  bool get isImage => imageUrl != null;
  bool get isFootnoteReference => footnoteReferenceId != null;

  _InlineToken withLink(String url) {
    if (isImage || isFootnoteReference) {
      return this;
    }
    return _InlineToken.text(text: text, style: style, linkUrl: url);
  }
}
