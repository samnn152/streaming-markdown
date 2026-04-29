part of '../view.dart';

extension _StreamingMarkdownSelectionBlockSegments
    on StreamingMarkdownRenderView {
  _MarkdownSelectionSegment _listSelectionSegment(
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final String raw = _normalizedRaw(node.raw);
    final _ParsedList parsed = _parseListNode(node);
    if (parsed.items.isEmpty) {
      return _MarkdownSelectionSegment.plain(
        plainText: raw,
        markdownText: raw,
        preserveBlockMarkdownOnPartial: true,
      );
    }

    final List<_ListSelectionItem> items = <_ListSelectionItem>[];
    final StringBuffer plain = StringBuffer();
    for (int i = 0; i < parsed.items.length; i++) {
      final _ParsedListItem item = parsed.items[i];
      if (i > 0) {
        plain.write('\n');
      }
      final _MarkdownSelectionSegment segment = _inlineSelectionSegment(
        item.text,
        markdownText: item.text,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
      final int start = plain.length;
      plain.write(segment.plainText);
      items.add(
        _ListSelectionItem(
          item: item,
          segment: segment,
          start: start,
          end: plain.length,
        ),
      );
    }

    return _MarkdownSelectionSegment(
      pieces: <_MarkdownSelectionPiece>[
        _MarkdownSelectionPiece(plainText: plain.toString(), markdownText: raw),
      ],
      fallbackMarkdownText: raw,
      rangeMarkdownBuilder: (int selectionStart, int selectionEnd) {
        return _markdownListForPlainRange(
          items: items,
          selectionStart: selectionStart,
          selectionEnd: selectionEnd,
        );
      },
    );
  }

  String _markdownListForPlainRange({
    required List<_ListSelectionItem> items,
    required int selectionStart,
    required int selectionEnd,
  }) {
    final List<String> lines = <String>[];
    for (final _ListSelectionItem item in items) {
      if (item.segment.plainText.isEmpty ||
          selectionEnd <= item.start ||
          selectionStart >= item.end) {
        continue;
      }
      final int localStart =
          (selectionStart - item.start).clamp(0, item.segment.plainText.length);
      final int localEnd =
          (selectionEnd - item.start).clamp(0, item.segment.plainText.length);
      final String markdown = item.segment.markdownForPlainRange(
        localStart,
        localEnd,
      );
      if (markdown.isEmpty) {
        continue;
      }
      lines.add('${_listItemMarkdownPrefix(item.item)}$markdown');
    }
    return lines.join('\n');
  }

  String _listItemMarkdownPrefix(_ParsedListItem item) {
    final String indent = '  ' * item.level;
    final String marker = item.ordered ? '${item.order}.' : '-';
    final String task = item.taskState == null
        ? ''
        : item.taskState!
            ? ' [x]'
            : ' [ ]';
    return '$indent$marker$task ';
  }

  _MarkdownSelectionSegment _quoteSelectionSegment(MarkdownRenderNode node) {
    final String raw = _normalizedRaw(node.raw);
    final String plain = _quoteText(node);
    return _MarkdownSelectionSegment(
      pieces: <_MarkdownSelectionPiece>[
        _MarkdownSelectionPiece(plainText: plain, markdownText: raw),
      ],
      fallbackMarkdownText: raw,
      rangeMarkdownBuilder: (int selectionStart, int selectionEnd) {
        final int start = selectionStart.clamp(0, plain.length);
        final int end = selectionEnd.clamp(0, plain.length);
        if (start >= end) {
          return '';
        }
        return _prefixMarkdownQuote(plain.substring(start, end));
      },
    );
  }

  String _prefixMarkdownQuote(String text) {
    return text
        .split('\n')
        .map((String line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
  }

  _MarkdownSelectionSegment _codeBlockSelectionSegment(
    MarkdownRenderNode node,
  ) {
    final String raw = _normalizedRaw(node.raw);
    final String code = _codeText(node);
    return _MarkdownSelectionSegment(
      pieces: <_MarkdownSelectionPiece>[
        _MarkdownSelectionPiece(plainText: code, markdownText: raw),
      ],
      fallbackMarkdownText: raw,
      rangeMarkdownBuilder: (int selectionStart, int selectionEnd) {
        final int start = selectionStart.clamp(0, code.length);
        final int end = selectionEnd.clamp(0, code.length);
        if (start >= end) {
          return '';
        }
        return _wrapMarkdownCodeBlock(node.raw, code.substring(start, end));
      },
    );
  }

  String _wrapMarkdownCodeBlock(String raw, String code) {
    final String normalized = _normalizedRaw(raw);
    final RegExpMatch? opener = RegExp(
      r'^\s*(```+|~~~+)\s*([^\n]*)',
    ).firstMatch(normalized);
    final String fence = opener?.group(1) ?? '```';
    final String info = opener?.group(2)?.trimRight() ?? '';
    final StringBuffer out = StringBuffer();
    out.write(fence);
    if (info.isNotEmpty) {
      out.write(info.trimLeft());
    }
    out.write('\n');
    out.write(code.trimRight());
    out.write('\n');
    out.write(fence);
    return out.toString();
  }
}
