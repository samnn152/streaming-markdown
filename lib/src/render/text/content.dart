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
    return _htmlSelectionUnitsForNodes(fragment.nodes).join('\n');
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

List<String> _htmlSelectionUnitsForNodes(List<html_dom.Node> nodes) {
  final List<String> units = <String>[];
  void append(String text) {
    if (text.trim().isNotEmpty) {
      units.add(text);
    }
  }

  for (final html_dom.Node node in nodes) {
    if (node is html_dom.Text) {
      append(_normalizeHtmlInlineText(node.text).trim());
      continue;
    }
    if (node is! html_dom.Element) {
      continue;
    }
    final String tag = (node.localName ?? '').toLowerCase();
    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
      case 'p':
        append(_htmlInlineSelectionText(node.nodes));
        break;
      case 'pre':
        append(node.text.trimRight());
        break;
      case 'blockquote':
        units.addAll(_htmlSelectionUnitsForNodes(node.nodes));
        break;
      case 'ul':
      case 'ol':
        for (final html_dom.Element item in node.children.where(
          (html_dom.Element child) => child.localName == 'li',
        )) {
          units.addAll(_htmlSelectionUnitsForNodes(item.nodes));
        }
        break;
      case 'table':
        for (final html_dom.Element row in node.querySelectorAll('tr')) {
          for (final html_dom.Element cell in row.children.where(
            (html_dom.Element child) =>
                child.localName == 'th' || child.localName == 'td',
          )) {
            append(_htmlInlineSelectionText(cell.nodes));
          }
        }
        break;
      case 'img':
        append(_htmlImageSelectionText(node));
        break;
      case 'a':
        append(_htmlStandaloneAnchorSelectionText(node));
        break;
      case 'hr':
      case 'br':
        break;
      default:
        final bool hasBlockChildren =
            node.nodes.whereType<html_dom.Element>().any(
                  (html_dom.Element child) => _HtmlBlockRenderer._blockTags
                      .contains((child.localName ?? '').toLowerCase()),
                );
        if (hasBlockChildren) {
          units.addAll(_htmlSelectionUnitsForNodes(node.nodes));
        } else {
          append(_htmlInlineSelectionText(node.nodes));
        }
        break;
    }
  }
  return units;
}

String _htmlInlineSelectionText(List<html_dom.Node> nodes) {
  final StringBuffer out = StringBuffer();
  for (final html_dom.Node node in nodes) {
    if (node is html_dom.Text) {
      out.write(_normalizeHtmlInlineText(node.text));
      continue;
    }
    if (node is! html_dom.Element) {
      continue;
    }
    final String tag = (node.localName ?? '').toLowerCase();
    switch (tag) {
      case 'br':
        out.write('\n');
        break;
      case 'code':
        out.write(node.text);
        break;
      case 'a':
        final String href = (node.attributes['href'] ?? '').trim();
        final String label = _normalizeHtmlInlineText(node.text).trim();
        out.write(label.isEmpty ? href : label);
        break;
      case 'img':
        out.write(_htmlImageSelectionText(node));
        break;
      default:
        out.write(_htmlInlineSelectionText(node.nodes));
        break;
    }
  }
  return out.toString();
}

String _htmlImageSelectionText(html_dom.Element element) {
  final String alt = _normalizeHtmlInlineText(
    element.attributes['alt'] ?? '',
  ).trim();
  if (alt.isNotEmpty) {
    return '[image: $alt]';
  }
  final String src = _normalizeHtmlInlineText(
    element.attributes['src'] ?? '',
  ).trim();
  return src.isEmpty ? '[image]' : '[image: $src]';
}

String _htmlStandaloneAnchorSelectionText(html_dom.Element element) {
  final String href = (element.attributes['href'] ?? '').trim();
  final String label = _normalizeHtmlInlineText(element.text).trim();
  if (href.isEmpty) {
    return label;
  }
  return label.isEmpty ? href : '$label ($href)';
}

String _normalizeHtmlInlineText(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), ' ');
}
