part of '../view.dart';

class _HtmlBlockRenderer {
  _HtmlBlockRenderer({
    required this.context,
    required this.onLinkTap,
    required this.paragraphTextStyle,
  });

  static const Color _borderColor = Color(0xFF30363D);
  static const Color _codeBackgroundColor = Color(0xFF161B22);
  static const Color _codeForegroundColor = Color(0xFFE6EDF3);
  static const Color _linkColor = Color(0xFF58A6FF);
  static const Set<String> _blockTags = <String>{
    'address',
    'article',
    'aside',
    'blockquote',
    'dd',
    'div',
    'dl',
    'dt',
    'figcaption',
    'figure',
    'footer',
    'form',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'li',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'ul',
  };

  final BuildContext context;
  final ValueChanged<String> onLinkTap;
  final TextStyle? paragraphTextStyle;

  TextStyle get _paragraphStyle =>
      paragraphTextStyle ??
      Theme.of(context).textTheme.bodyLarge ??
      const TextStyle(fontSize: 15, height: 1.45, color: _codeForegroundColor);

  List<Widget> buildBlocks(
    List<html_dom.Node> nodes, {
    int listDepth = 0,
  }) {
    final List<Widget> out = <Widget>[];
    for (final html_dom.Node node in nodes) {
      if (node is html_dom.Text) {
        final Widget paragraph = _buildParagraphFromText(node.text);
        if (paragraph is! SizedBox) {
          out.add(paragraph);
        }
        continue;
      }
      if (node is! html_dom.Element) {
        continue;
      }
      out.addAll(_buildElement(node, listDepth: listDepth));
    }
    return out;
  }

  static List<Widget> withSpacing(List<Widget> children, double spacing) {
    if (children.length < 2) {
      return children;
    }
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i < children.length - 1) {
        out.add(SizedBox(height: spacing));
      }
    }
    return out;
  }

  List<Widget> _buildElement(html_dom.Element element,
      {required int listDepth}) {
    final String tag = (element.localName ?? '').toLowerCase();
    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return <Widget>[_buildHeading(element, level: int.parse(tag[1]))];
      case 'p':
        return <Widget>[_buildParagraph(element.nodes)];
      case 'pre':
        return <Widget>[_buildCodeBlock(element.text)];
      case 'blockquote':
        return <Widget>[_buildBlockQuote(element, listDepth: listDepth)];
      case 'ul':
        return <Widget>[
          _buildList(element, ordered: false, listDepth: listDepth)
        ];
      case 'ol':
        return <Widget>[
          _buildList(element, ordered: true, listDepth: listDepth)
        ];
      case 'table':
        return <Widget>[_buildTable(element)];
      case 'img':
        return <Widget>[_buildImage(element)];
      case 'hr':
        return <Widget>[
          const Divider(height: 1, thickness: 1, color: _borderColor),
        ];
      case 'a':
        return <Widget>[_buildStandaloneAnchor(element)];
      case 'br':
        return const <Widget>[];
      default:
        if (_containsBlockChildren(element)) {
          return buildBlocks(element.nodes, listDepth: listDepth);
        }
        final Widget paragraph = _buildParagraph(element.nodes);
        if (paragraph is SizedBox) {
          return const <Widget>[];
        }
        return <Widget>[paragraph];
    }
  }
}
