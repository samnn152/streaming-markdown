part of '../view.dart';

extension _StreamingMarkdownDelimiterParsing on StreamingMarkdownRenderView {
  List<_FootnoteDefinition> _parseFootnoteDefinitions(String raw) {
    final List<String> lines = _normalizedRaw(raw).split('\n');
    if (lines.isEmpty) {
      return <_FootnoteDefinition>[];
    }

    final RegExp definitionLine = RegExp(r'^\s{0,3}\[\^([^\]]+)\]:\s*(.*)$');
    final List<_FootnoteDefinition> definitions = <_FootnoteDefinition>[];
    String? currentId;
    List<String> currentBody = <String>[];

    void flush() {
      final String? id = currentId;
      if (id == null) {
        return;
      }
      definitions.add(
        _FootnoteDefinition(id: id, body: currentBody.join('\n').trim()),
      );
    }

    for (final String line in lines) {
      final RegExpMatch? definition = definitionLine.firstMatch(line);
      if (definition != null) {
        flush();
        currentId = definition.group(1)!.trim();
        currentBody = <String>[definition.group(2)!.trim()];
        continue;
      }
      if (currentId == null) {
        continue;
      }
      if (line.trim().isEmpty) {
        currentBody.add('');
        continue;
      }
      currentBody.add(line.replaceFirst(RegExp(r'^\s{0,4}'), '').trimRight());
    }
    flush();

    return definitions;
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
    if (!_canOpenDelimiter(text, start, delimiter)) {
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

  bool _canOpenDelimiter(String text, int start, String delimiter) {
    if (!delimiter.startsWith('_')) {
      return true;
    }
    final int previousIndex = start - 1;
    final int nextIndex = start + delimiter.length;
    if (previousIndex < 0 || nextIndex >= text.length) {
      return true;
    }
    final int previous = text.codeUnitAt(previousIndex);
    final int next = text.codeUnitAt(nextIndex);
    return !_isAsciiAlphanumeric(previous) || !_isAsciiAlphanumeric(next);
  }

  bool _isAsciiAlphanumeric(int codeUnit) {
    return (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122);
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
}
