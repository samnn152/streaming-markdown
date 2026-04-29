part of '../view.dart';

extension _StreamingMarkdownContentParsing on StreamingMarkdownRenderView {
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

  String _htmlBlockSelectionText(String raw) {
    final html_dom.DocumentFragment fragment = html_parser.parseFragment(raw);
    return _firstHtmlSelectionText(fragment.nodes).trim();
  }

  String _firstHtmlSelectionText(List<html_dom.Node> nodes) {
    for (final html_dom.Node node in nodes) {
      final String text = _htmlSelectionTextForNode(node);
      if (text.trim().isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _htmlSelectionTextForNode(html_dom.Node node) {
    if (node is html_dom.Text) {
      return node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (node is! html_dom.Element) {
      return '';
    }

    final String tag = (node.localName ?? '').toLowerCase();
    if (tag == 'img') {
      return (node.attributes['alt'] ?? node.attributes['src'] ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    if (tag == 'br') {
      return '\n';
    }

    final String text = _firstHtmlSelectionText(node.nodes);
    if (text.trim().isNotEmpty) {
      return text;
    }
    return node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _headingText(MarkdownRenderNode node) {
    final String source = node.content.trim().isNotEmpty
        ? node.content.trim()
        : _normalizedRaw(node.raw).trim();
    if (node.type == 'setext_heading') {
      return _stripSetextDelimiter(source);
    }
    return source.replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '').trim();
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
      if (lines.length >= 2 && RegExp(r'^\s*=+\s*$').hasMatch(lines.last)) {
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

  String _stripSetextDelimiter(String text) {
    final List<String> lines = _normalizedRaw(text).split('\n');
    if (lines.length < 2 || !_isSetextDelimiterLine(lines.last)) {
      return text.trim();
    }
    return lines.take(lines.length - 1).join('\n').trim();
  }

  bool _isSetextDelimiterLine(String line) {
    return RegExp(r'^\s{0,3}(=+|-+)\s*$').hasMatch(line);
  }
}
