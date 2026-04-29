part of '../view.dart';

extension _HtmlBlockRendererInline on _HtmlBlockRenderer {
  Widget _buildImage(html_dom.Element element) {
    final String src = (element.attributes['src'] ?? '').trim();
    final String alt = (element.attributes['alt'] ?? '').trim();
    if (src.isEmpty) {
      return _buildParagraphFromText(alt);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        src,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: double.infinity,
          color: _HtmlBlockRenderer._codeBackgroundColor,
          padding: const EdgeInsets.all(8),
          child: Text(
            alt.isEmpty ? src : alt,
            style: _paragraphStyle.copyWith(color: const Color(0xFF9CA3AF)),
          ),
        ),
      ),
    );
  }

  Widget _buildStandaloneAnchor(html_dom.Element element) {
    final String href = (element.attributes['href'] ?? '').trim();
    final String label = _normalizeInlineText(element.text).trim();
    if (href.isEmpty) {
      return _buildParagraphFromText(label);
    }
    final String visible = label.isEmpty ? href : '$label ($href)';
    return InkWell(
      onTap: () => onLinkTap(href),
      child: Text(
        visible,
        style: _paragraphStyle.copyWith(
          color: _HtmlBlockRenderer._linkColor,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  List<InlineSpan> _buildInlineSpans(
      List<html_dom.Node> nodes, TextStyle style) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (final html_dom.Node node in nodes) {
      if (node is html_dom.Text) {
        final String text = _normalizeInlineText(node.text);
        if (text.isNotEmpty) {
          spans.add(TextSpan(text: text));
        }
        continue;
      }
      if (node is! html_dom.Element) {
        continue;
      }
      final String tag = (node.localName ?? '').toLowerCase();
      switch (tag) {
        case 'br':
          spans.add(const TextSpan(text: '\n'));
          break;
        case 'strong':
        case 'b':
          spans.add(
            TextSpan(
              style: style.copyWith(fontWeight: FontWeight.w700),
              children: _buildInlineSpans(node.nodes, style),
            ),
          );
          break;
        case 'em':
        case 'i':
          spans.add(
            TextSpan(
              style: style.copyWith(fontStyle: FontStyle.italic),
              children: _buildInlineSpans(node.nodes, style),
            ),
          );
          break;
        case 'code':
          spans.add(
            TextSpan(
              style: style.copyWith(
                fontFamily: 'monospace',
                color: _HtmlBlockRenderer._codeForegroundColor,
                backgroundColor: _HtmlBlockRenderer._codeBackgroundColor,
              ),
              text: node.text,
            ),
          );
          break;
        case 'a':
          final String href = (node.attributes['href'] ?? '').trim();
          final String label = _normalizeInlineText(node.text).trim();
          final String visible = label.isEmpty ? href : label;
          if (visible.isNotEmpty) {
            final TextStyle linkStyle = style.copyWith(
              color: _HtmlBlockRenderer._linkColor,
              decoration: TextDecoration.underline,
            );
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: href.isEmpty
                    ? Text(visible, style: linkStyle)
                    : MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onLinkTap(href),
                          child: Text(visible, style: linkStyle),
                        ),
                      ),
              ),
            );
          }
          break;
        default:
          spans.addAll(_buildInlineSpans(node.nodes, style));
          break;
      }
    }
    return spans;
  }

  bool _containsBlockChildren(html_dom.Element element) {
    for (final html_dom.Node node in element.nodes) {
      if (node is! html_dom.Element) {
        continue;
      }
      if (_HtmlBlockRenderer._blockTags
          .contains((node.localName ?? '').toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String _normalizeInlineText(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ');
  }
}
