part of '../view.dart';

extension _HtmlBlockRendererInline on _HtmlBlockRenderer {
  Widget _buildImage(html_dom.Element element) {
    final String src = (element.attributes['src'] ?? '').trim();
    final String alt = (element.attributes['alt'] ?? '').trim();
    final Widget imageWidget = src.isEmpty
        ? Container(
            width: double.infinity,
            color: _HtmlBlockRenderer._codeBackgroundColor,
            padding: const EdgeInsets.all(8),
            child: Text(
              alt.isEmpty ? 'Image unavailable' : alt,
              style: _paragraphStyle.copyWith(color: const Color(0xFF9CA3AF)),
            ),
          )
        : ClipRRect(
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
                  style: _paragraphStyle.copyWith(
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          );
    final String plain = _htmlImageSelectionText(element);
    final (int, int) selectionStarts = _selectionStartsFor(plain);
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    if (registrar == null) {
      return imageWidget;
    }
    return _SelectableInlineTextProxy(
      text: TextSpan(style: _paragraphStyle, text: plain),
      plainText: plain,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScale: _markdownTextScaleOf(context),
      registrar: registrar,
      selectionRegistry: _MarkdownInlineSelectionRegistryScope.maybeOf(context),
      absolutePlainTextStart: selectionStarts.$1,
      compactPlainTextStart: selectionStarts.$2,
      selectionColor: selectionColor,
      atomic: true,
      child: SelectionContainer.disabled(child: imageWidget),
    );
  }

  Widget _buildStandaloneAnchor(html_dom.Element element) {
    final String href = (element.attributes['href'] ?? '').trim();
    final String label = _normalizeInlineText(element.text).trim();
    if (href.isEmpty) {
      return _buildParagraphFromText(label);
    }
    final String visible = _htmlStandaloneAnchorSelectionText(element);
    final TextStyle style = _paragraphStyle.copyWith(
      color: _HtmlBlockRenderer._linkColor,
      decoration: TextDecoration.underline,
    );
    final Widget anchor = InkWell(
      onTap: () => onLinkTap(href),
      child: Text(visible, style: style),
    );
    final (int, int) selectionStarts = _selectionStartsFor(visible);
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    if (registrar == null) {
      return anchor;
    }
    return _SelectableInlineTextProxy(
      text: TextSpan(style: style, text: visible),
      plainText: visible,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScale: _markdownTextScaleOf(context),
      registrar: registrar,
      selectionRegistry: _MarkdownInlineSelectionRegistryScope.maybeOf(context),
      absolutePlainTextStart: selectionStarts.$1,
      compactPlainTextStart: selectionStarts.$2,
      selectionColor: selectionColor,
      child: SelectionContainer.disabled(child: anchor),
    );
  }

  List<InlineSpan> _buildInlineSpans(
    List<html_dom.Node> nodes,
    TextStyle style, {
    _HtmlInlineSelectionCursor? selectionCursor,
  }) {
    final _HtmlInlineSelectionCursor cursor =
        selectionCursor ?? _HtmlInlineSelectionCursor();
    final List<InlineSpan> spans = <InlineSpan>[];
    for (final html_dom.Node node in nodes) {
      if (node is html_dom.Text) {
        final String text = _normalizeInlineText(node.text);
        if (text.isNotEmpty) {
          spans.add(TextSpan(text: text));
          cursor.advance(text.length);
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
          cursor.advance(1);
          break;
        case 'strong':
        case 'b':
          spans.add(
            TextSpan(
              style: style.copyWith(fontWeight: FontWeight.w700),
              children: _buildInlineSpans(
                node.nodes,
                style,
                selectionCursor: cursor,
              ),
            ),
          );
          break;
        case 'em':
        case 'i':
          spans.add(
            TextSpan(
              style: style.copyWith(fontStyle: FontStyle.italic),
              children: _buildInlineSpans(
                node.nodes,
                style,
                selectionCursor: cursor,
              ),
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
          cursor.advance(node.text.length);
          break;
        case 'a':
          final String href = (node.attributes['href'] ?? '').trim();
          final String label = _normalizeInlineText(node.text).trim();
          final String visible = label.isEmpty ? href : label;
          if (visible.isNotEmpty) {
            final int semanticStart = cursor.offset;
            final TextStyle linkStyle = style.copyWith(
              color: _HtmlBlockRenderer._linkColor,
              decoration: TextDecoration.underline,
            );
            cursor.advance(visible.length);
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _MarkdownSelectableTextSpan(
                  semanticRange: TextRange(
                    start: semanticStart,
                    end: cursor.offset,
                  ),
                  text: visible,
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
              ),
            );
          }
          break;
        case 'img':
          final String semanticText = _htmlImageSelectionText(node);
          final int start = cursor.offset;
          cursor.advance(semanticText.length);
          final String src = (node.attributes['src'] ?? '').trim();
          final String alt = (node.attributes['alt'] ?? '').trim();
          final double height = (style.fontSize ?? 16) * 1.4;
          final Widget image = src.isEmpty
              ? Text(alt.isEmpty ? 'image' : alt, style: style)
              : Image.network(
                  src,
                  height: height,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    alt.isEmpty ? 'image' : alt,
                    style: style,
                  ),
                );
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _MarkdownSelectableAtomicSpan(
                semanticRange: TextRange(start: start, end: cursor.offset),
                child: image,
              ),
            ),
          );
          break;
        default:
          spans.addAll(
            _buildInlineSpans(
              node.nodes,
              style,
              selectionCursor: cursor,
            ),
          );
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
    return _normalizeHtmlInlineText(raw);
  }
}

class _HtmlInlineSelectionCursor {
  int offset = 0;

  void advance(int length) {
    offset += length;
  }
}
