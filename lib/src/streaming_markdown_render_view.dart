import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'markdown_render_node.dart';

class StreamingMarkdownRenderView extends StatelessWidget {
  const StreamingMarkdownRenderView({
    super.key,
    required this.nodes,
    this.emptyPlaceholder = 'Không có node block đủ dữ liệu để render.',
    this.padding = const EdgeInsets.all(12),
    this.allowUnclosedInlineDelimiters = false,
  });

  final List<MarkdownRenderNode> nodes;
  final String emptyPlaceholder;
  final EdgeInsetsGeometry padding;
  final bool allowUnclosedInlineDelimiters;

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

    final List<InlineSpan> spans = <InlineSpan>[];
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
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: InkWell(
              onTap: () => _onLinkPressed(context, token.linkUrl!),
              child: Text(token.text, style: style),
            ),
          ),
        );
        continue;
      }
      spans.add(TextSpan(text: token.text, style: style));
    }

    return RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(style: resolvedStyle, children: spans),
    );
  }

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

  _ParsedTable? _parseMarkdownTable(String raw) {
    final List<String> lines = raw
        .split('\n')
        .map((String line) => line.trimRight())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) {
      return null;
    }

    int delimiterIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (_isTableDelimiterRow(lines[i])) {
        delimiterIndex = i;
        break;
      }
    }
    if (delimiterIndex <= 0) {
      return null;
    }

    final List<String> headers = _splitTableRow(lines[delimiterIndex - 1]);
    if (headers.isEmpty) {
      return null;
    }

    final int width = headers.length;
    final List<List<String>> rows = <List<String>>[];
    for (int i = delimiterIndex + 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || !line.contains('|')) {
        continue;
      }

      final List<String> row = _splitTableRow(line);
      if (row.isEmpty) {
        continue;
      }
      while (row.length < width) {
        row.add('');
      }
      if (row.length > width) {
        row.removeRange(width, row.length);
      }
      rows.add(row);
    }

    return _ParsedTable(headers: headers, rows: rows);
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

      final _DelimitedMatch? bold = _matchAnyDelimited(text, i, const <String>[
        '**',
        '__',
      ], allowUnclosedDelimiters: allowUnclosedDelimiters);
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
    final Match? match = RegExp(r'^\[\^([^\]]+)\]').matchAsPrefix(text, start);
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
    return key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
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

  void _onLinkPressed(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied link: $url')));
  }
}

final class _ParsedList {
  const _ParsedList({required this.items});

  final List<_ParsedListItem> items;
}

final class _ParsedListItem {
  const _ParsedListItem({
    required this.level,
    required this.ordered,
    required this.order,
    required this.taskState,
    required this.text,
  });

  final int level;
  final bool ordered;
  final int order;
  final bool? taskState;
  final String text;
}

final class _ParsedTable {
  const _ParsedTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

final class _CalloutData {
  const _CalloutData({
    required this.kind,
    required this.title,
    required this.body,
  });

  final String kind;
  final String title;
  final String body;
}

final class _DelimitedMatch {
  const _DelimitedMatch({required this.inner, required this.end});

  final String inner;
  final int end;
}

final class _InlineImageMatch {
  const _InlineImageMatch({
    required this.alt,
    required this.url,
    required this.end,
  });

  final String alt;
  final String url;
  final int end;
}

final class _InlineLinkMatch {
  const _InlineLinkMatch({
    required this.label,
    required this.url,
    required this.end,
  });

  final String label;
  final String url;
  final int end;
}

final class _FootnoteReferenceMatch {
  const _FootnoteReferenceMatch({required this.id, required this.end});

  final String id;
  final int end;
}

final class _FootnoteDefinition {
  const _FootnoteDefinition({required this.id, required this.body});

  final String id;
  final String body;
}

final class _InlineStyle {
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

final class _InlineToken {
  const _InlineToken.text({
    required this.text,
    required this.style,
    this.linkUrl,
  }) : altText = '',
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

typedef _BlockBuilder =
    Widget Function(
      BuildContext context,
      MarkdownRenderNode node,
      Map<String, String> linkReferences,
    );

class _BlockRenderHost extends StatefulWidget {
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
  State<_BlockRenderHost> createState() => _BlockRenderHostState();
}

class _BlockRenderHostState extends State<_BlockRenderHost> {
  Widget? _cachedChild;
  String? _lastSignature;
  int? _lastThemeHash;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final int themeHash = Theme.of(context).hashCode;
    if (_cachedChild == null || _lastThemeHash != themeHash) {
      _lastThemeHash = themeHash;
      _rebuildCache();
    }
  }

  @override
  void didUpdateWidget(covariant _BlockRenderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastSignature != widget.signature) {
      _rebuildCache();
    }
  }

  void _rebuildCache() {
    _lastSignature = widget.signature;
    _cachedChild = widget.builder(context, widget.node, widget.linkReferences);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: _cachedChild ?? const SizedBox.shrink());
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
