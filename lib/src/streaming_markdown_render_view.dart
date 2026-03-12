import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'markdown_render_node.dart';

part 'streaming_markdown_render_text_parsing.dart';

class StreamingMarkdownRenderView extends StatelessWidget
    with _StreamingMarkdownTextParsing {
  const StreamingMarkdownRenderView({
    super.key,
    required this.nodes,
    this.emptyPlaceholder = 'Không có node block đủ dữ liệu để render.',
    this.padding = const EdgeInsets.all(12),
    this.allowUnclosedInlineDelimiters = false,
    this.tokenArrivalDelay = Duration.zero,
    this.tokenFadeInRelativeToDelay = 0,
    this.tokenFadeInDuration,
    this.tokenFadeInCurve = Curves.easeOut,
    this.debugTokenHighlight = false,
  });

  final List<MarkdownRenderNode> nodes;
  final String emptyPlaceholder;
  final EdgeInsetsGeometry padding;
  final bool allowUnclosedInlineDelimiters;
  final Duration tokenArrivalDelay;
  final double tokenFadeInRelativeToDelay;
  final Duration? tokenFadeInDuration;
  final Curve tokenFadeInCurve;
  final bool debugTokenHighlight;

  Duration _resolvedTokenFadeInDuration() {
    final Duration? absolute = tokenFadeInDuration;
    if (absolute != null) {
      return absolute <= Duration.zero ? Duration.zero : absolute;
    }
    if (tokenFadeInRelativeToDelay <= 0 || tokenArrivalDelay <= Duration.zero) {
      return Duration.zero;
    }
    final int micros =
        (tokenArrivalDelay.inMicroseconds * tokenFadeInRelativeToDelay).round();
    if (micros <= 0) {
      return Duration.zero;
    }
    return Duration(microseconds: micros);
  }

  @override
  Widget build(BuildContext context) {
    final List<MarkdownRenderNode> blocks = _collectRenderableBlocks(nodes);
    if (blocks.isEmpty) {
      return Center(child: Text(emptyPlaceholder, textAlign: TextAlign.center));
    }

    final Map<String, String> linkReferences = _extractLinkReferences(nodes);
    final String refsDigest = _linkReferencesDigest(linkReferences);

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < blocks.length; i++) ...[
            _BlockRenderHost(
              key: ValueKey<String>(_blockIdentity(blocks[i])),
              signature: _blockSignature(blocks[i], refsDigest),
              node: blocks[i],
              linkReferences: linkReferences,
              builder: _buildRenderedBlockWithRefs,
            ),
            if (i < blocks.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  List<MarkdownRenderNode> _collectRenderableBlocks(
    List<MarkdownRenderNode> nodes,
  ) {
    if (nodes.isEmpty) {
      return <MarkdownRenderNode>[];
    }

    final List<MarkdownRenderNode> blockNodes = nodes
        .where((MarkdownRenderNode node) => _isRenderableBlockNode(node.type))
        .toList(growable: false);
    if (blockNodes.isEmpty) {
      return <MarkdownRenderNode>[];
    }

    final List<MarkdownRenderNode> sorted = blockNodes.toList(growable: false)
      ..sort((MarkdownRenderNode a, MarkdownRenderNode b) {
        final int byStart = a.startByte.compareTo(b.startByte);
        if (byStart != 0) {
          return byStart;
        }
        final int byEnd = b.endByte.compareTo(a.endByte);
        if (byEnd != 0) {
          return byEnd;
        }
        return a.depth.compareTo(b.depth);
      });

    final Set<String> seenSpans = <String>{};
    final List<MarkdownRenderNode> out = <MarkdownRenderNode>[];
    MarkdownRenderNode? lastContainer;

    for (final MarkdownRenderNode node in sorted) {
      final String spanKey = '${node.startByte}:${node.endByte}:${node.type}';
      if (!seenSpans.add(spanKey)) {
        continue;
      }

      if (lastContainer != null &&
          node.startByte >= lastContainer.startByte &&
          node.endByte <= lastContainer.endByte &&
          node.depth > lastContainer.depth) {
        continue;
      }

      out.add(node);
      if (_containerConsumesChildren(node.type)) {
        lastContainer = node;
      } else if (lastContainer != null &&
          node.endByte > lastContainer.endByte) {
        lastContainer = null;
      }
    }

    return out;
  }

  bool _isRenderableBlockNode(String type) {
    switch (type) {
      case 'atx_heading':
      case 'setext_heading':
      case 'paragraph':
      case 'fenced_code_block':
      case 'indented_code_block':
      case 'block_quote':
      case 'list':
      case 'thematic_break':
      case 'html_block':
      case 'pipe_table':
      case 'table':
      case 'footnote_definition':
      case 'link_reference_definition':
      case 'front_matter':
        return true;
      default:
        return type.endsWith('_block') || type.endsWith('_heading');
    }
  }

  bool _containerConsumesChildren(String type) {
    return type == 'block_quote' ||
        type == 'list' ||
        type == 'fenced_code_block' ||
        type == 'indented_code_block' ||
        type == 'pipe_table' ||
        type == 'table' ||
        type == 'html_block' ||
        type == 'front_matter';
  }

  String _blockIdentity(MarkdownRenderNode node) {
    return '${node.type}:${node.startByte}:${node.depth}';
  }

  String _blockSignature(MarkdownRenderNode node, String refsDigest) {
    return '${node.type}:${node.startByte}:${node.endByte}:${node.startRow}:${node.endRow}:${node.raw.hashCode}:$refsDigest';
  }

  String _linkReferencesDigest(Map<String, String> linkReferences) {
    if (linkReferences.isEmpty) {
      return '0';
    }
    final List<MapEntry<String, String>> entries =
        linkReferences.entries.toList(growable: false)..sort(
          (MapEntry<String, String> a, MapEntry<String, String> b) =>
              a.key.compareTo(b.key),
        );
    final StringBuffer buffer = StringBuffer();
    for (final MapEntry<String, String> entry in entries) {
      buffer
        ..write(entry.key)
        ..write('=')
        ..write(entry.value)
        ..write(';');
    }
    return buffer.toString().hashCode.toString();
  }

  Widget _buildRenderedBlockWithRefs(
    BuildContext context,
    MarkdownRenderNode node,
    Map<String, String> linkReferences,
  ) {
    return _buildRenderedBlock(context, node, linkReferences: linkReferences);
  }

  Widget _buildRenderedBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
  }) {
    switch (node.type) {
      case 'atx_heading':
      case 'setext_heading':
        return _buildHeadingBlock(
          context,
          node,
          linkReferences: linkReferences,
        );
      case 'paragraph':
        final _ParsedTable? paragraphTable = _parseMarkdownTable(
          _normalizedRaw(node.raw),
        );
        if (paragraphTable != null) {
          return _buildTableWidget(
            context,
            paragraphTable,
            linkReferences: linkReferences,
          );
        }
        return _buildParagraphBlock(
          context,
          _paragraphText(node),
          linkReferences: linkReferences,
        );
      case 'list':
      case 'list_item':
        return _buildListBlock(context, node, linkReferences: linkReferences);
      case 'block_quote':
        return _buildQuoteBlock(context, node, linkReferences: linkReferences);
      case 'fenced_code_block':
      case 'indented_code_block':
        return _buildCodeBlock(node);
      case 'thematic_break':
        return const Divider(height: 1, thickness: 1, color: Color(0xFF30363D));
      case 'pipe_table':
      case 'table':
        return _buildTableBlock(context, node, linkReferences: linkReferences);
      case 'html_block':
        return _HtmlBlockCard(html: _normalizedRaw(node.raw));
      case 'front_matter':
      case 'link_reference_definition':
        return _buildMetadataBlock(
          context,
          node,
          linkReferences: linkReferences,
        );
      case 'footnote_definition':
        return _buildFootnoteDefinitionBlock(
          context,
          node,
          linkReferences: linkReferences,
        );
      default:
        return _buildParagraphBlock(
          context,
          _paragraphText(node),
          linkReferences: linkReferences,
        );
    }
  }

  Widget _buildHeadingBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
  }) {
    final int level = _headingLevelForNode(node);
    final TextTheme textTheme = Theme.of(context).textTheme;
    TextStyle style;
    switch (level) {
      case 1:
        style =
            textTheme.headlineMedium ??
            const TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
        break;
      case 2:
        style =
            textTheme.headlineSmall ??
            const TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
        break;
      case 3:
        style =
            textTheme.titleLarge ??
            const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
        break;
      case 4:
        style =
            textTheme.titleMedium ??
            const TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
        break;
      case 5:
        style =
            textTheme.titleSmall ??
            const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
        break;
      default:
        style =
            textTheme.bodyLarge ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
        break;
    }

    return _buildInlineMarkdown(
      context,
      _headingText(node),
      baseStyle: style,
      linkReferences: linkReferences,
    );
  }

  Widget _buildParagraphBlock(
    BuildContext context,
    String text, {
    required Map<String, String> linkReferences,
  }) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final _InlineImageMatch? image = _matchSingleInlineImage(text);
    if (image != null) {
      return _buildImageBlock(context, image);
    }

    return _buildInlineMarkdown(
      context,
      text,
      baseStyle: Theme.of(context).textTheme.bodyLarge,
      linkReferences: linkReferences,
    );
  }

  Widget _buildListBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
  }) {
    final _ParsedList parsed = _parseListNode(node);
    if (parsed.items.isEmpty) {
      return _buildParagraphBlock(
        context,
        _contentOrRaw(node),
        linkReferences: linkReferences,
      );
    }

    final TextStyle baseStyle =
        Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < parsed.items.length; i++) ...[
          Padding(
            key: ValueKey<String>('list_item_${parsed.items[i].stableKey}'),
            padding: EdgeInsets.only(left: parsed.items[i].level * 18.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: _buildListMarker(parsed.items[i], baseStyle),
                ),
                Expanded(
                  child: _buildInlineMarkdown(
                    context,
                    parsed.items[i].text,
                    baseStyle: baseStyle,
                    linkReferences: linkReferences,
                  ),
                ),
              ],
            ),
          ),
          if (i < parsed.items.length - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildQuoteBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
  }) {
    final String text = _quoteText(node);
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final _CalloutData? callout = _parseCallout(text);
    final Color calloutColor = _calloutColor(callout?.kind);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: calloutColor, width: 3)),
        color: const Color(0xFF161B22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (callout != null) ...[
            Row(
              children: [
                Icon(_calloutIcon(callout.kind), size: 16, color: calloutColor),
                const SizedBox(width: 6),
                Text(
                  callout.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: calloutColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          _buildInlineMarkdown(
            context,
            callout?.body ?? text,
            baseStyle: Theme.of(context).textTheme.bodyLarge,
            linkReferences: linkReferences,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(MarkdownRenderNode node) {
    final String code = _codeText(node);
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }

    final String language = _codeLanguage(node.raw);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Text(
                language,
                style: const TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                color: Color(0xFFE6EDF3),
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
  }) {
    final _ParsedTable? table = _parseMarkdownTable(_normalizedRaw(node.raw));
    if (table == null) {
      return _buildParagraphBlock(
        context,
        _contentOrRaw(node),
        linkReferences: linkReferences,
      );
    }

    return _buildTableWidget(context, table, linkReferences: linkReferences);
  }

  Widget _buildTableWidget(
    BuildContext context,
    _ParsedTable table, {
    required Map<String, String> linkReferences,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.all(color: const Color(0xFF30363D)),
        children: <TableRow>[
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF21262D)),
            children: table.headers
                .map(
                  (String cell) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildInlineMarkdown(
                      context,
                      cell,
                      baseStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      linkReferences: linkReferences,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          ...table.rows.map((List<String> row) {
            return TableRow(
              children: row
                  .map(
                    (String cell) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: _buildInlineMarkdown(
                        context,
                        cell,
                        baseStyle: const TextStyle(fontSize: 13),
                        linkReferences: linkReferences,
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMetadataBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
  }) {
    final String text = _normalizedRaw(node.raw).trim().isNotEmpty
        ? _normalizedRaw(node.raw).trim()
        : _contentOrRaw(node);
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: _buildInlineMarkdown(
        context,
        text,
        baseStyle: const TextStyle(
          color: Color(0xFFF0F6FC),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        linkReferences: linkReferences,
      ),
    );
  }

  Widget _buildFootnoteDefinitionBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
  }) {
    final _FootnoteDefinition? definition = _parseFootnoteDefinition(node.raw);
    if (definition == null) {
      return _buildMetadataBlock(context, node, linkReferences: linkReferences);
    }

    final TextStyle bodyStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '[${definition.id}]',
            style: bodyStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8B949E),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildInlineMarkdown(
            context,
            definition.body,
            baseStyle: bodyStyle,
            linkReferences: linkReferences,
          ),
        ),
      ],
    );
  }

  Widget _buildImageBlock(BuildContext context, _InlineImageMatch image) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            image.url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: 120,
              width: double.infinity,
              color: const Color(0xFF161B22),
              alignment: Alignment.center,
              child: const Text(
                'Image unavailable',
                style: TextStyle(color: Color(0xFFF0F6FC)),
              ),
            ),
          ),
        ),
        if (image.alt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            image.alt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF8B949E),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildListMarker(_ParsedListItem item, TextStyle baseStyle) {
    if (item.taskState != null) {
      return Icon(
        item.taskState! ? Icons.check_box : Icons.check_box_outline_blank,
        size: 16,
        color: item.taskState!
            ? const Color(0xFF2EA043)
            : const Color(0xFF8B949E),
      );
    }
    if (item.ordered) {
      return Text('${item.order}.', style: baseStyle);
    }
    return Text('•', style: baseStyle);
  }

  Widget _buildInlineMarkdown(
    BuildContext context,
    String text, {
    TextStyle? baseStyle,
    Map<String, String> linkReferences = const <String, String>{},
  }) {
    final String normalized = text.replaceAll('\r', '');
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final TextStyle resolvedStyle =
        baseStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final List<_InlineToken> tokens = _parseInlineTokens(
      normalized,
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    if (tokens.isEmpty) {
      return Text(normalized, style: resolvedStyle);
    }
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();

    final List<InlineSpan> spans = <InlineSpan>[];
    int visualTokenIndex = 0;
    for (final _InlineToken token in tokens) {
      if (token.isImage) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Text(
                token.altText.isEmpty ? 'image' : 'image: ${token.altText}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFF0F6FC)),
              ),
            ),
          ),
        );
        continue;
      }

      if (token.style.code) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                token.text,
                style: const TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
        continue;
      }

      if (token.isFootnoteReference) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.aboveBaseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Text(
                '[${token.footnoteReferenceId}]',
                style: const TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
        continue;
      }

      TextStyle style = resolvedStyle;
      if (token.style.bold) {
        style = style.copyWith(fontWeight: FontWeight.w700);
      }
      if (token.style.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
      if (token.style.strikethrough) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (token.linkUrl != null && token.linkUrl!.isNotEmpty) {
        style = style.copyWith(
          color: const Color(0xFF58A6FF),
          decoration: TextDecoration.underline,
        );
        visualTokenIndex = _appendTokenizedTextSpans(
          spans: spans,
          text: token.text,
          style: style,
          startTokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          onTap: () => _onLinkPressed(context, token.linkUrl!),
        );
        continue;
      }
      visualTokenIndex = _appendTokenizedTextSpans(
        spans: spans,
        text: token.text,
        style: style,
        startTokenIndex: visualTokenIndex,
        fadeDuration: tokenFadeDuration,
        fadeCurve: tokenFadeInCurve,
      );
    }

    return RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(style: resolvedStyle, children: spans),
    );
  }

  static const List<Color> _tokenDebugColors = <Color>[
    Color(0xFFFFF3BF),
    Color(0xFFD3F9D8),
    Color(0xFFFFDEEB),
    Color(0xFFD0EBFF),
    Color(0xFFE5DBFF),
    Color(0xFFFFE8CC),
  ];

  int _appendTokenizedTextSpans({
    required List<InlineSpan> spans,
    required String text,
    required TextStyle style,
    required int startTokenIndex,
    required Duration fadeDuration,
    required Curve fadeCurve,
    VoidCallback? onTap,
  }) {
    int tokenIndex = startTokenIndex;
    for (final RegExpMatch match in RegExp(r'\S+|\s+').allMatches(text)) {
      final String piece = match.group(0) ?? '';
      if (piece.isEmpty) {
        continue;
      }

      if (piece.trim().isEmpty) {
        spans.add(TextSpan(text: piece, style: style));
        continue;
      }

      final Widget tokenWidget;
      if (debugTokenHighlight) {
        final Color bgColor =
            _tokenDebugColors[tokenIndex % _tokenDebugColors.length];
        tokenWidget = Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            piece,
            style: style.copyWith(
              color: style.color ?? const Color(0xFF0D1117),
            ),
          ),
        );
      } else {
        tokenWidget = Text(piece, style: style);
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _FadeInTokenHost(
            key: ValueKey<String>('token_${tokenIndex}_${piece.hashCode}'),
            duration: fadeDuration,
            curve: fadeCurve,
            child: onTap == null
                ? tokenWidget
                : (debugTokenHighlight
                      ? InkWell(
                          onTap: onTap,
                          borderRadius: BorderRadius.circular(4),
                          child: tokenWidget,
                        )
                      : GestureDetector(onTap: onTap, child: tokenWidget)),
          ),
        ),
      );
      tokenIndex += 1;
    }
    return tokenIndex;
  }

  void _onLinkPressed(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied link: $url')));
  }
}

typedef _BlockBuilder =
    Widget Function(
      BuildContext context,
      MarkdownRenderNode node,
      Map<String, String> linkReferences,
    );

class _BlockRenderHost extends StatelessWidget {
  const _BlockRenderHost({
    super.key,
    required this.signature,
    required this.node,
    required this.linkReferences,
    required this.builder,
  });

  final String signature;
  final MarkdownRenderNode node;
  final Map<String, String> linkReferences;
  final _BlockBuilder builder;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: builder(context, node, linkReferences));
  }
}

class _FadeInTokenHost extends StatefulWidget {
  const _FadeInTokenHost({
    required this.duration,
    required this.curve,
    required this.child,
    super.key,
  });

  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_FadeInTokenHost> createState() => _FadeInTokenHostState();
}

class _FadeInTokenHostState extends State<_FadeInTokenHost> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _visible = widget.duration <= Duration.zero;
    if (_visible) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duration <= Duration.zero) {
      return widget.child;
    }
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: widget.duration,
      curve: widget.curve,
      child: widget.child,
    );
  }
}

class _HtmlBlockCard extends StatelessWidget {
  const _HtmlBlockCard({required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _HtmlBlockWebView(
        key: ValueKey<int>(html.hashCode),
        htmlDocument: _htmlDocumentForWebView(html),
        fallbackText: html,
      ),
    );
  }

  String _htmlDocumentForWebView(String rawHtml) {
    if (RegExp(r'<\s*html[\s>]', caseSensitive: false).hasMatch(rawHtml)) {
      return rawHtml;
    }

    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <style>
      :root { color-scheme: dark; }
      body {
        margin: 12px;
        color: #f0f6fc;
        background: #0d1117;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        line-height: 1.45;
      }
      a { color: #58a6ff; }
      table { border-collapse: collapse; }
      th, td {
        border: 1px solid #30363d;
        padding: 6px 8px;
      }
      code {
        background: #161b22;
        color: #e6edf3;
        border-radius: 4px;
        padding: 1px 4px;
      }
      pre {
        background: #161b22;
        color: #e6edf3;
        border-radius: 6px;
        padding: 10px;
        overflow-x: auto;
      }
    </style>
  </head>
  <body>$rawHtml</body>
</html>
''';
  }
}

class _HtmlBlockWebView extends StatefulWidget {
  const _HtmlBlockWebView({
    super.key,
    required this.htmlDocument,
    required this.fallbackText,
  });

  final String htmlDocument;
  final String fallbackText;

  @override
  State<_HtmlBlockWebView> createState() => _HtmlBlockWebViewState();
}

class _HtmlBlockWebViewState extends State<_HtmlBlockWebView> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant _HtmlBlockWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.htmlDocument == widget.htmlDocument) {
      return;
    }

    final WebViewController? controller = _controller;
    if (controller != null) {
      unawaited(controller.loadHtmlString(widget.htmlDocument));
      return;
    }

    _initController();
  }

  void _initController() {
    try {
      final WebViewController controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0D1117))
        ..loadHtmlString(widget.htmlDocument);
      _controller = controller;
    } catch (_) {
      _controller = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final WebViewController? controller = _controller;
    if (controller == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: SelectableText(
          widget.fallbackText,
          style: const TextStyle(
            color: Color(0xFFF0F6FC),
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
          ),
        ),
      );
    }

    return WebViewWidget(controller: controller);
  }
}
