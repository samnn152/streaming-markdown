import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'dart:async';
import 'dart:collection';

import 'markdown_render_node.dart';

part 'streaming_markdown_render_text_parsing.dart';

/// Custom builder hook for overriding a rendered markdown block widget.
typedef StreamingMarkdownBlockBuilder = Widget? Function(
  BuildContext context,
  StreamingMarkdownBlockBuildContext block,
);

/// Snapshot passed into [StreamingMarkdownTokenAnimationBuilder].
@immutable
class StreamingMarkdownAnimatedToken {
  const StreamingMarkdownAnimatedToken({
    required this.child,
    required this.animation,
  });

  final Widget child;
  final Animation<double> animation;

  double get value => animation.value;
}

/// Custom animation hook for each rendered token.
typedef StreamingMarkdownTokenAnimationBuilder = Widget Function(
  BuildContext context,
  StreamingMarkdownAnimatedToken token,
);

/// Context object passed to [StreamingMarkdownBlockBuilder].
class StreamingMarkdownBlockBuildContext {
  const StreamingMarkdownBlockBuildContext({
    required this.node,
    required this.linkReferences,
    required this.defaultWidget,
  });

  /// Source render node for this block.
  final MarkdownRenderNode node;

  /// Link reference map extracted from current node list.
  final Map<String, String> linkReferences;

  /// Default widget produced by internal renderer.
  final Widget defaultWidget;
}

/// Theme/customization data for [StreamingMarkdownRenderView].
class StreamingMarkdownThemeData {
  const StreamingMarkdownThemeData({
    this.blockSpacing = 12,
    this.paragraphTextStyle,
    this.heading1TextStyle,
    this.heading2TextStyle,
    this.heading3TextStyle,
    this.heading4TextStyle,
    this.heading5TextStyle,
    this.heading6TextStyle,
    this.linkTextStyle,
    this.inlineCodeTextStyle,
    this.inlineCodeBackgroundColor,
    this.codeBlockBackgroundColor,
    this.codeBlockHeaderBackgroundColor,
    this.codeBlockLanguageTextStyle,
    this.codeBlockTextStyle,
    this.quoteBackgroundColor,
    this.metadataBackgroundColor,
    this.metadataBorderColor,
    this.metadataTextStyle,
    this.tableBorderColor,
    this.tableHeaderBackgroundColor,
    this.thematicBreakColor,
    this.imageErrorBackgroundColor,
    this.imageErrorTextStyle,
    this.selectionColor,
  });

  final double blockSpacing;
  final TextStyle? paragraphTextStyle;
  final TextStyle? heading1TextStyle;
  final TextStyle? heading2TextStyle;
  final TextStyle? heading3TextStyle;
  final TextStyle? heading4TextStyle;
  final TextStyle? heading5TextStyle;
  final TextStyle? heading6TextStyle;
  final TextStyle? linkTextStyle;
  final TextStyle? inlineCodeTextStyle;
  final Color? inlineCodeBackgroundColor;
  final Color? codeBlockBackgroundColor;
  final Color? codeBlockHeaderBackgroundColor;
  final TextStyle? codeBlockLanguageTextStyle;
  final TextStyle? codeBlockTextStyle;
  final Color? quoteBackgroundColor;
  final Color? metadataBackgroundColor;
  final Color? metadataBorderColor;
  final TextStyle? metadataTextStyle;
  final Color? tableBorderColor;
  final Color? tableHeaderBackgroundColor;
  final Color? thematicBreakColor;
  final Color? imageErrorBackgroundColor;
  final TextStyle? imageErrorTextStyle;
  final Color? selectionColor;
}

/// Streaming markdown UI renderer.
///
/// Input is a list of [MarkdownRenderNode] blocks (typically produced by
/// [StreamingMarkdownParseWorker]). This widget focuses on real-time streaming
/// behavior: partial markdown tolerance, token-level fade-in, and optional text
/// selection support.
class StreamingMarkdownRenderView extends StatelessWidget
    with _StreamingMarkdownTextParsing {
  static final Map<String, _ParsedTable> _tableSnapshotCache =
      <String, _ParsedTable>{};
  static const int _tableSnapshotCacheLimit = 256;

  const StreamingMarkdownRenderView({
    super.key,
    required this.nodes,
    this.emptyPlaceholder = '',
    this.padding = const EdgeInsets.all(12),
    this.sliver = false,
    this.allowUnclosedInlineDelimiters = false,
    this.tokenArrivalDelay = Duration.zero,
    this.onTokenArrivalWait,
    this.tokenFadeInRelativeToDelay = 0,
    this.tokenFadeInDuration,
    this.tokenFadeInCurve = Curves.easeOut,
    this.tokenAnimationBuilder,
    this.debugTokenHighlight = false,
    this.enableTextSelection = false,
    this.markdownTheme = const StreamingMarkdownThemeData(),
    this.customBlockBuilder,
    this.onLinkTap,
  });

  final List<MarkdownRenderNode> nodes;
  final String emptyPlaceholder;
  final EdgeInsetsGeometry padding;
  final bool sliver;
  final bool allowUnclosedInlineDelimiters;
  final Duration tokenArrivalDelay;
  final VoidCallback? onTokenArrivalWait;
  final double tokenFadeInRelativeToDelay;
  final Duration? tokenFadeInDuration;
  final Curve tokenFadeInCurve;
  final StreamingMarkdownTokenAnimationBuilder? tokenAnimationBuilder;
  final bool debugTokenHighlight;
  final bool enableTextSelection;
  final StreamingMarkdownThemeData markdownTheme;
  final StreamingMarkdownBlockBuilder? customBlockBuilder;
  final ValueChanged<String>? onLinkTap;

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
      final Widget empty = Center(
        child: Text(emptyPlaceholder, textAlign: TextAlign.center),
      );
      if (!sliver) {
        return empty;
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(padding: padding, child: empty),
      );
    }

    final Map<String, String> linkReferences = _extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers = _extractFootnoteNumbers(nodes);
    final String refsDigest = _linkReferencesDigest(linkReferences);
    final String renderConfigDigest = _renderConfigDigest(context);

    final Widget content = _SequencedBlockList(
      blocks: blocks,
      sliver: sliver,
      padding: padding,
      blockSpacing: markdownTheme.blockSpacing,
      tokenArrivalDelay: tokenArrivalDelay,
      onWait: onTokenArrivalWait,
      blockIdentityBuilder: _blockIdentity,
      blockBuilder: (BuildContext context, MarkdownRenderNode block) {
        return _BlockRenderHost(
          key: ValueKey<String>(_blockIdentity(block)),
          signature: _blockSignature(
            block,
            refsDigest,
            renderConfigDigest,
          ),
          node: block,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
          builder: _buildRenderedBlockWithRefs,
        );
      },
    );

    if (!enableTextSelection || sliver) {
      return content;
    }
    return SelectionArea(child: content);
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
    final List<MarkdownRenderNode> normalized = _mergeOrphanTableFragments(
      sorted,
    );

    final Set<String> seenSpans = <String>{};
    final List<MarkdownRenderNode> out = <MarkdownRenderNode>[];
    MarkdownRenderNode? lastContainer;

    for (final MarkdownRenderNode node in normalized) {
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

  List<MarkdownRenderNode> _mergeOrphanTableFragments(
    List<MarkdownRenderNode> sorted,
  ) {
    final List<MarkdownRenderNode> out = <MarkdownRenderNode>[];
    int i = 0;
    while (i < sorted.length) {
      final MarkdownRenderNode node = sorted[i];
      if (!_isTableFragmentNode(node.type)) {
        out.add(node);
        i += 1;
        continue;
      }
      if (_isTableFragmentCoveredByContainer(node, sorted)) {
        i += 1;
        continue;
      }

      final List<MarkdownRenderNode> fragments = <MarkdownRenderNode>[node];
      int j = i + 1;
      while (j < sorted.length) {
        final MarkdownRenderNode candidate = sorted[j];
        if (!_isTableFragmentNode(candidate.type) ||
            _isTableFragmentCoveredByContainer(candidate, sorted)) {
          break;
        }
        final MarkdownRenderNode previous = fragments.last;
        if (candidate.startRow > previous.endRow + 1) {
          break;
        }
        fragments.add(candidate);
        j += 1;
      }

      final MarkdownRenderNode synthesized = _synthesizeTableNodeFromFragments(
        fragments,
      );
      final _ParsedTable? parsed = _parseMarkdownTable(
        _normalizedRaw(synthesized.raw),
        allowLooseWithoutDelimiter: true,
        minLooseRowsWithoutDelimiter: 2,
      );
      if (parsed == null) {
        out.add(node);
        i += 1;
        continue;
      }

      out.add(synthesized);
      i = j;
    }
    return out;
  }

  MarkdownRenderNode _synthesizeTableNodeFromFragments(
    List<MarkdownRenderNode> fragments,
  ) {
    int startByte = fragments.first.startByte;
    int endByte = fragments.first.endByte;
    int startRow = fragments.first.startRow;
    int endRow = fragments.first.endRow;
    int depth = fragments.first.depth;
    final StringBuffer raw = StringBuffer();
    for (int i = 0; i < fragments.length; i++) {
      final MarkdownRenderNode fragment = fragments[i];
      if (fragment.startByte < startByte) {
        startByte = fragment.startByte;
      }
      if (fragment.endByte > endByte) {
        endByte = fragment.endByte;
      }
      if (fragment.startRow < startRow) {
        startRow = fragment.startRow;
      }
      if (fragment.endRow > endRow) {
        endRow = fragment.endRow;
      }
      if (fragment.depth < depth) {
        depth = fragment.depth;
      }

      final String line = _normalizedRaw(fragment.raw).trim();
      if (line.isNotEmpty) {
        if (raw.isNotEmpty) {
          raw.writeln();
        }
        raw.write(line);
      }
    }

    return MarkdownRenderNode(
      type: 'pipe_table',
      depth: depth,
      startByte: startByte,
      endByte: endByte,
      startRow: startRow,
      endRow: endRow,
      raw: raw.toString(),
      content: raw.toString(),
    );
  }

  bool _isTableFragmentCoveredByContainer(
    MarkdownRenderNode node,
    List<MarkdownRenderNode> all,
  ) {
    for (final MarkdownRenderNode candidate in all) {
      if (!_isTableContainerNode(candidate.type)) {
        continue;
      }
      if (candidate.startByte <= node.startByte &&
          candidate.endByte >= node.endByte &&
          candidate.depth <= node.depth) {
        return true;
      }
    }
    return false;
  }

  bool _isTableContainerNode(String type) {
    return type == 'pipe_table' || type == 'table';
  }

  bool _isTableFragmentNode(String type) {
    return type == 'pipe_table_header' ||
        type == 'pipe_table_row' ||
        type == 'pipe_table_delimiter_row';
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
      case 'pipe_table_header':
      case 'pipe_table_row':
      case 'pipe_table_delimiter_row':
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

  String _tableSnapshotKey(MarkdownRenderNode node) {
    return '${node.startByte}:${node.startRow}:${node.depth}';
  }

  void _rememberTableSnapshot(MarkdownRenderNode node, _ParsedTable table) {
    final String key = _tableSnapshotKey(node);
    _tableSnapshotCache[key] = table;
    if (_tableSnapshotCache.length <= _tableSnapshotCacheLimit) {
      return;
    }
    final String firstKey = _tableSnapshotCache.keys.first;
    _tableSnapshotCache.remove(firstKey);
  }

  _ParsedTable? _readTableSnapshot(MarkdownRenderNode node) {
    return _tableSnapshotCache[_tableSnapshotKey(node)];
  }

  String _blockSignature(
    MarkdownRenderNode node,
    String refsDigest,
    String renderConfigDigest,
  ) {
    return '${node.type}:${node.startByte}:${node.endByte}:${node.startRow}:${node.endRow}:${node.raw.hashCode}:$refsDigest:$renderConfigDigest';
  }

  String _renderConfigDigest(BuildContext context) {
    final Duration resolvedFade = _resolvedTokenFadeInDuration();
    final StringBuffer buffer = StringBuffer()
      ..write(tokenArrivalDelay.inMicroseconds)
      ..write(':')
      ..write(onTokenArrivalWait.hashCode)
      ..write(':')
      ..write(resolvedFade.inMicroseconds)
      ..write(':')
      ..write(tokenFadeInCurve)
      ..write(':')
      ..write(tokenAnimationBuilder.hashCode)
      ..write(':')
      ..write(allowUnclosedInlineDelimiters)
      ..write(':')
      ..write(debugTokenHighlight)
      ..write(':')
      ..write(enableTextSelection)
      ..write(':')
      ..write(sliver)
      ..write(':')
      ..write(padding.hashCode)
      ..write(':')
      ..write(markdownTheme.hashCode)
      ..write(':')
      ..write(customBlockBuilder.hashCode)
      ..write(':')
      ..write(onLinkTap.hashCode)
      ..write(':')
      ..write(Theme.of(context).hashCode);
    return buffer.toString().hashCode.toString();
  }

  String _linkReferencesDigest(Map<String, String> linkReferences) {
    if (linkReferences.isEmpty) {
      return '0';
    }
    final List<MapEntry<String, String>> entries =
        linkReferences.entries.toList(growable: false)
          ..sort(
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
    Map<String, int> footnoteNumbers,
  ) {
    final Widget defaultWidget = _buildRenderedBlock(
      context,
      node,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    final StreamingMarkdownBlockBuilder? builder = customBlockBuilder;
    if (builder == null) {
      return defaultWidget;
    }
    return builder(
          context,
          StreamingMarkdownBlockBuildContext(
            node: node,
            linkReferences: linkReferences,
            defaultWidget: defaultWidget,
          ),
        ) ??
        defaultWidget;
  }

  Widget _buildRenderedBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    switch (node.type) {
      case 'atx_heading':
      case 'setext_heading':
        return _buildHeadingBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'paragraph':
        final String normalizedRaw = _normalizedRaw(node.raw);
        _ParsedTable? paragraphTable = _parseMarkdownTable(normalizedRaw);
        if (paragraphTable == null && normalizedRaw.contains('\n')) {
          paragraphTable = _parseMarkdownTable(
            normalizedRaw,
            allowLooseWithoutDelimiter: true,
            minLooseRowsWithoutDelimiter: 2,
          );
        }
        if (paragraphTable != null) {
          return _buildTableWidget(
            context,
            paragraphTable,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          );
        }
        return _buildParagraphBlock(
          context,
          _paragraphText(node),
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'list':
      case 'list_item':
        return _buildListBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'block_quote':
        return _buildQuoteBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'fenced_code_block':
      case 'indented_code_block':
        return _buildCodeBlock(node);
      case 'thematic_break':
        return Divider(
          height: 1,
          thickness: 1,
          color: markdownTheme.thematicBreakColor ?? const Color(0xFF30363D),
        );
      case 'pipe_table':
      case 'table':
      case 'pipe_table_header':
      case 'pipe_table_row':
      case 'pipe_table_delimiter_row':
        return _buildTableBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'html_block':
        return _HtmlBlockCard(
          html: _normalizedRaw(node.raw),
          onLinkTap: (String url) => _onLinkPressed(context, url),
          paragraphTextStyle: markdownTheme.paragraphTextStyle ??
              Theme.of(context).textTheme.bodyLarge,
        );
      case 'front_matter':
      case 'link_reference_definition':
        return _buildMetadataBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'footnote_definition':
        return _buildFootnoteDefinitionBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      default:
        return _buildParagraphBlock(
          context,
          _paragraphText(node),
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
    }
  }

  Widget _buildHeadingBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final int level = _headingLevelForNode(node);
    final TextTheme textTheme = Theme.of(context).textTheme;
    TextStyle style;
    switch (level) {
      case 1:
        style = markdownTheme.heading1TextStyle ??
            textTheme.headlineMedium ??
            const TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
        break;
      case 2:
        style = markdownTheme.heading2TextStyle ??
            textTheme.headlineSmall ??
            const TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
        break;
      case 3:
        style = markdownTheme.heading3TextStyle ??
            textTheme.titleLarge ??
            const TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
        break;
      case 4:
        style = markdownTheme.heading4TextStyle ??
            textTheme.titleMedium ??
            const TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
        break;
      case 5:
        style = markdownTheme.heading5TextStyle ??
            textTheme.titleSmall ??
            const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
        break;
      default:
        style = markdownTheme.heading6TextStyle ??
            textTheme.bodyLarge ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
        break;
    }

    return _buildInlineMarkdown(
      context,
      _headingText(node),
      baseStyle: style,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
  }

  Widget _buildParagraphBlock(
    BuildContext context,
    String text, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
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
      baseStyle: markdownTheme.paragraphTextStyle ??
          Theme.of(context).textTheme.bodyLarge,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
  }

  Widget _buildListBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _ParsedList parsed = _parseListNode(node);
    if (parsed.items.isEmpty) {
      return _buildParagraphBlock(
        context,
        _contentOrRaw(node),
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
    }

    final TextStyle baseStyle = markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);

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
                    footnoteNumbers: footnoteNumbers,
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
    required Map<String, int> footnoteNumbers,
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
        color: markdownTheme.quoteBackgroundColor ?? const Color(0xFF161B22),
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
            baseStyle: markdownTheme.paragraphTextStyle ??
                Theme.of(context).textTheme.bodyLarge,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
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
        color:
            markdownTheme.codeBlockBackgroundColor ?? const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: markdownTheme.codeBlockHeaderBackgroundColor ??
                    const Color(0xFF161B22),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Text(
                language,
                style: markdownTheme.codeBlockLanguageTextStyle ??
                    const TextStyle(
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
              style: markdownTheme.codeBlockTextStyle ??
                  const TextStyle(
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
    required Map<String, int> footnoteNumbers,
  }) {
    final _ParsedTable? parsed = _parseMarkdownTable(
      _normalizedRaw(node.raw),
      allowLooseWithoutDelimiter: true,
      minLooseRowsWithoutDelimiter: 2,
    );
    if (parsed != null) {
      _rememberTableSnapshot(node, parsed);
      return _buildTableWidget(
        context,
        parsed,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
    }

    final _ParsedTable? snapshot = _readTableSnapshot(node);
    if (snapshot != null) {
      return _buildTableWidget(
        context,
        snapshot,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
    }

    return _buildParagraphBlock(
      context,
      _contentOrRaw(node),
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
  }

  Widget _buildTableWidget(
    BuildContext context,
    _ParsedTable table, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder.all(
          color: markdownTheme.tableBorderColor ?? const Color(0xFF30363D),
        ),
        children: <TableRow>[
          TableRow(
            decoration: BoxDecoration(
              color: markdownTheme.tableHeaderBackgroundColor ??
                  const Color(0xFF21262D),
            ),
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
                      footnoteNumbers: footnoteNumbers,
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
                        footnoteNumbers: footnoteNumbers,
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
    required Map<String, int> footnoteNumbers,
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
        color: markdownTheme.metadataBackgroundColor ?? const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: markdownTheme.metadataBorderColor ?? const Color(0xFF30363D),
        ),
      ),
      child: _buildInlineMarkdown(
        context,
        text,
        baseStyle: markdownTheme.metadataTextStyle ??
            const TextStyle(
              color: Color(0xFFF0F6FC),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      ),
    );
  }

  Widget _buildFootnoteDefinitionBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _FootnoteDefinition? definition = _parseFootnoteDefinition(node.raw);
    if (definition == null) {
      return _buildMetadataBlock(
        context,
        node,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
    }

    final TextStyle bodyStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final int? footnoteNumber = _footnoteNumberForId(
      footnoteNumbers,
      definition.id,
    );
    final String marker = footnoteNumber?.toString() ?? definition.id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '$marker.',
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
            footnoteNumbers: footnoteNumbers,
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
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              width: double.infinity,
              color: markdownTheme.imageErrorBackgroundColor ??
                  const Color(0xFF161B22),
              alignment: Alignment.center,
              child: Text(
                'Image unavailable',
                style: markdownTheme.imageErrorTextStyle ??
                    const TextStyle(color: Color(0xFFF0F6FC)),
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
      return SizedBox(
        height: _listMarkerLineHeight(baseStyle),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            item.taskState! ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: item.taskState!
                ? const Color(0xFF2EA043)
                : const Color(0xFF8B949E),
          ),
        ),
      );
    }
    if (item.ordered) {
      return Text('${item.order}.', style: baseStyle);
    }
    return Text('•', style: baseStyle);
  }

  double _listMarkerLineHeight(TextStyle baseStyle) {
    final double fontSize = baseStyle.fontSize ?? 16;
    final double height = baseStyle.height ?? 1.5;
    return fontSize * height;
  }

  Widget _buildInlineMarkdown(
    BuildContext context,
    String text, {
    TextStyle? baseStyle,
    Map<String, String> linkReferences = const <String, String>{},
    Map<String, int> footnoteNumbers = const <String, int>{},
  }) {
    final String normalized = text.replaceAll('\r', '');
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final TextStyle resolvedStyle = baseStyle ??
        markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final bool showSelectionOverlay = enableTextSelection;
    final bool animatePerWord = !showSelectionOverlay;
    final List<_InlineToken> tokens = _parseInlineTokens(
      normalized,
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    if (tokens.isEmpty) {
      return Text(normalized, style: resolvedStyle);
    }
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final Duration tokenStaggerDelay = tokenArrivalDelay;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenStaggerDelay;

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
        final TextStyle inlineCodeStyle = markdownTheme.inlineCodeTextStyle ??
            const TextStyle(
              color: Color(0xFFE6EDF3),
              fontFamily: 'monospace',
              fontSize: 12,
            );
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: markdownTheme.inlineCodeBackgroundColor ??
                    const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(token.text, style: inlineCodeStyle),
            ),
          ),
        );
        continue;
      }

      if (token.isFootnoteReference) {
        final int? footnoteNumber = _footnoteNumberForId(
          footnoteNumbers,
          token.footnoteReferenceId!,
        );
        final String label =
            footnoteNumber?.toString() ?? token.footnoteReferenceId!;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.aboveBaseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Text(
                label,
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
        style = style.merge(
          markdownTheme.linkTextStyle ??
              const TextStyle(
                color: Color(0xFF58A6FF),
                decoration: TextDecoration.underline,
              ),
        );
        visualTokenIndex = _appendTokenizedTextSpans(
          spans: spans,
          text: token.text,
          style: style,
          startTokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animatePerWord: animatePerWord,
          onTap: showSelectionOverlay
              ? null
              : () => _onLinkPressed(context, token.linkUrl!),
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
        tokenStaggerDelay: resolvedTokenStep,
        tokenScheduleOrigin: tokenScheduleOrigin,
        tokenAnimationBuilder: tokenAnimationBuilder,
        animatePerWord: animatePerWord,
      );
    }

    final Widget animatedRichText = RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(style: resolvedStyle, children: spans),
    );
    final Widget visibleAnimatedLayer =
        showSelectionOverlay && tokenFadeDuration > Duration.zero
            ? _FadeInTokenHost(
                key: ValueKey<String>(
                  'sel_inline_${normalized.hashCode}_${resolvedStyle.hashCode}',
                ),
                duration: tokenFadeDuration,
                curve: tokenFadeInCurve,
                scheduledStart: tokenScheduleOrigin,
                animationBuilder: tokenAnimationBuilder,
                child: animatedRichText,
              )
            : animatedRichText;
    if (!showSelectionOverlay) {
      return visibleAnimatedLayer;
    }

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Positioned.fill(
          child: _SelectableInlineTextOverlay(
            tokens: tokens,
            baseStyle: resolvedStyle,
            footnoteNumbers: footnoteNumbers,
            textScaler: MediaQuery.textScalerOf(context),
            selectionColor:
                markdownTheme.selectionColor ?? const Color(0x6658A6FF),
            onLinkTap: (String url) => _onLinkPressed(context, url),
          ),
        ),
        IgnorePointer(child: visibleAnimatedLayer),
      ],
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
    required Duration tokenStaggerDelay,
    required DateTime? tokenScheduleOrigin,
    required StreamingMarkdownTokenAnimationBuilder? tokenAnimationBuilder,
    required bool animatePerWord,
    VoidCallback? onTap,
  }) {
    if (!animatePerWord) {
      spans.add(TextSpan(text: text, style: style));
      return startTokenIndex + 1;
    }

    int tokenIndex = startTokenIndex;
    for (final RegExpMatch match in RegExp(r'\S+\s*|\s+').allMatches(text)) {
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
            initialDelay: tokenScheduleOrigin == null
                ? tokenStaggerDelay * (tokenIndex - startTokenIndex)
                : Duration.zero,
            scheduledStart: tokenScheduleOrigin?.add(
              tokenStaggerDelay * (tokenIndex - startTokenIndex),
            ),
            duration: fadeDuration,
            curve: fadeCurve,
            animationBuilder: tokenAnimationBuilder,
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
    final ValueChanged<String>? callback = onLinkTap;
    if (callback != null) {
      callback(url);
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied link: $url')));
  }
}

class _SelectableInlineTextOverlay extends StatefulWidget {
  const _SelectableInlineTextOverlay({
    required this.tokens,
    required this.baseStyle,
    required this.footnoteNumbers,
    required this.textScaler,
    required this.selectionColor,
    required this.onLinkTap,
  });

  final List<_InlineToken> tokens;
  final TextStyle baseStyle;
  final Map<String, int> footnoteNumbers;
  final TextScaler textScaler;
  final Color selectionColor;
  final ValueChanged<String> onLinkTap;

  @override
  State<_SelectableInlineTextOverlay> createState() =>
      _SelectableInlineTextOverlayState();
}

class _SelectableInlineTextOverlayState
    extends State<_SelectableInlineTextOverlay> {
  List<TapGestureRecognizer?> _linkRecognizers = <TapGestureRecognizer?>[];

  @override
  void initState() {
    super.initState();
    _replaceRecognizers();
  }

  @override
  void didUpdateWidget(covariant _SelectableInlineTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _replaceRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _replaceRecognizers() {
    _disposeRecognizers();
    _linkRecognizers = widget.tokens.map((token) {
      final String? url = token.linkUrl;
      if (url == null || url.isEmpty) {
        return null;
      }
      return TapGestureRecognizer()
        ..onTap = () {
          widget.onLinkTap(url);
        };
    }).toList(growable: false);
  }

  void _disposeRecognizers() {
    for (final TapGestureRecognizer? recognizer in _linkRecognizers) {
      recognizer?.dispose();
    }
    _linkRecognizers = <TapGestureRecognizer?>[];
  }

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < widget.tokens.length; i++) {
      final _InlineToken token = widget.tokens[i];
      if (token.isImage) {
        final String imageText =
            token.altText.isEmpty ? '[image]' : '[image: ${token.altText}]';
        spans.add(
          TextSpan(
            text: imageText,
            style: _selectionOverlayStyle(
              widget.baseStyle.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        );
        continue;
      }

      if (token.isFootnoteReference) {
        final int? footnoteNumber = _footnoteNumberForId(
          widget.footnoteNumbers,
          token.footnoteReferenceId!,
        );
        final String label =
            footnoteNumber?.toString() ?? token.footnoteReferenceId!;
        spans.add(
          TextSpan(
            text: label,
            style: _selectionOverlayStyle(
              widget.baseStyle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        continue;
      }

      TextStyle style = widget.baseStyle;
      if (token.style.bold) {
        style = style.copyWith(fontWeight: FontWeight.w700);
      }
      if (token.style.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
      if (token.style.strikethrough) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (token.style.code) {
        style = style.copyWith(fontFamily: 'monospace', fontSize: 12);
      }
      if (token.linkUrl != null && token.linkUrl!.isNotEmpty) {
        style = style.copyWith(decoration: TextDecoration.underline);
      }

      spans.add(
        TextSpan(
          text: token.text,
          style: _selectionOverlayStyle(style),
          recognizer: _linkRecognizers[i],
        ),
      );
    }

    return RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: widget.textScaler,
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor: widget.selectionColor,
      text: TextSpan(style: widget.baseStyle, children: spans),
    );
  }
}

TextStyle _selectionOverlayStyle(TextStyle style) {
  return style.copyWith(
    color: Colors.transparent,
    backgroundColor: Colors.transparent,
    decorationColor: Colors.transparent,
    shadows: const <Shadow>[],
  );
}

typedef _BlockBuilder = Widget Function(
  BuildContext context,
  MarkdownRenderNode node,
  Map<String, String> linkReferences,
  Map<String, int> footnoteNumbers,
);

class _SequencedBlockList extends StatefulWidget {
  const _SequencedBlockList({
    required this.blocks,
    required this.sliver,
    required this.padding,
    required this.blockSpacing,
    required this.tokenArrivalDelay,
    required this.blockIdentityBuilder,
    required this.blockBuilder,
    this.onWait,
  });

  final List<MarkdownRenderNode> blocks;
  final bool sliver;
  final EdgeInsetsGeometry padding;
  final double blockSpacing;
  final Duration tokenArrivalDelay;
  final VoidCallback? onWait;
  final String Function(MarkdownRenderNode node) blockIdentityBuilder;
  final Widget Function(BuildContext context, MarkdownRenderNode node)
      blockBuilder;

  @override
  State<_SequencedBlockList> createState() => _SequencedBlockListState();
}

class _SequencedBlockListState extends State<_SequencedBlockList> {
  final Set<String> _visibleIds = <String>{};
  final LinkedHashSet<String> _pendingIds = LinkedHashSet<String>();
  final Map<String, DateTime> _revealedAt = <String, DateTime>{};
  Timer? _revealTimer;
  bool _isWaiting = false;

  @override
  void initState() {
    super.initState();
    _syncSchedule();
  }

  @override
  void didUpdateWidget(covariant _SequencedBlockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSchedule();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _syncSchedule() {
    final List<String> orderedIds =
        widget.blocks.map(widget.blockIdentityBuilder).toList(growable: false);
    final Set<String> activeIds = orderedIds.toSet();

    _visibleIds.removeWhere((String id) => !activeIds.contains(id));
    _pendingIds.removeWhere((String id) => !activeIds.contains(id));
    _revealedAt.removeWhere((String id, DateTime _) => !activeIds.contains(id));

    if (orderedIds.isEmpty) {
      _revealTimer?.cancel();
      _pendingIds.clear();
      if (_visibleIds.isNotEmpty && mounted) {
        setState(() {
          _visibleIds.clear();
        });
      } else {
        _visibleIds.clear();
      }
      _isWaiting = false;
      return;
    }

    bool queuedNew = false;
    for (final String id in orderedIds) {
      if (_visibleIds.contains(id) || _pendingIds.contains(id)) {
        continue;
      }
      _pendingIds.add(id);
      queuedNew = true;
    }

    if (queuedNew) {
      _isWaiting = false;
      if (_revealTimer == null) {
        _drainQueue();
      }
      return;
    }

    if (_pendingIds.isEmpty && _revealTimer == null) {
      _enterWaiting();
    }
  }

  void _drainQueue() {
    if (!mounted) {
      return;
    }
    if (_pendingIds.isEmpty) {
      _enterWaiting();
      return;
    }

    final String nextId = _pendingIds.first;
    _pendingIds.remove(nextId);
    final MarkdownRenderNode? revealedNode = _nodeForId(nextId);
    final DateTime revealedAt = DateTime.now();
    setState(() {
      _visibleIds.add(nextId);
      _revealedAt[nextId] = revealedAt;
    });

    if (_pendingIds.isEmpty) {
      _enterWaiting();
      return;
    }

    final Duration delay = _nextDequeueDelayAfterReveal(revealedNode);
    _revealTimer = Timer(delay, () {
      _revealTimer = null;
      _drainQueue();
    });
  }

  MarkdownRenderNode? _nodeForId(String id) {
    for (final MarkdownRenderNode node in widget.blocks) {
      if (widget.blockIdentityBuilder(node) == id) {
        return node;
      }
    }
    return null;
  }

  Duration _nextDequeueDelayAfterReveal(MarkdownRenderNode? node) {
    if (widget.tokenArrivalDelay <= Duration.zero || node == null) {
      return Duration.zero;
    }
    final int tokens = _tokenCountForNode(node);
    if (tokens <= 1) {
      return widget.tokenArrivalDelay;
    }
    return widget.tokenArrivalDelay * tokens;
  }

  int _tokenCountForNode(MarkdownRenderNode node) {
    final String text =
        (node.content.isNotEmpty ? node.content : node.raw).trim();
    if (text.isEmpty) {
      return 1;
    }
    final int count = RegExp(r'\S+').allMatches(text).length;
    return count <= 0 ? 1 : count;
  }

  void _enterWaiting() {
    if (_isWaiting) {
      return;
    }
    _isWaiting = true;
    widget.onWait?.call();
  }

  @override
  Widget build(BuildContext context) {
    final List<MarkdownRenderNode> visibleBlocks = widget.blocks
        .where(
          (MarkdownRenderNode node) =>
              _visibleIds.contains(widget.blockIdentityBuilder(node)),
        )
        .toList(growable: false);

    if (widget.sliver) {
      return SliverPadding(
        padding: widget.padding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
            if (i.isOdd) {
              return SizedBox(height: widget.blockSpacing);
            }
            final MarkdownRenderNode node = visibleBlocks[i ~/ 2];
            final String id = widget.blockIdentityBuilder(node);
            return _RevealScheduleScope(
              revealedAt: _revealedAt[id],
              tokenArrivalDelay: widget.tokenArrivalDelay,
              child: widget.blockBuilder(context, node),
            );
          },
              childCount:
                  visibleBlocks.isEmpty ? 0 : visibleBlocks.length * 2 - 1),
        ),
      );
    }

    final List<Widget> blockChildren = <Widget>[
      for (int i = 0; i < visibleBlocks.length; i++) ...[
        _RevealScheduleScope(
          revealedAt:
              _revealedAt[widget.blockIdentityBuilder(visibleBlocks[i])],
          tokenArrivalDelay: widget.tokenArrivalDelay,
          child: widget.blockBuilder(context, visibleBlocks[i]),
        ),
        if (i < visibleBlocks.length - 1) SizedBox(height: widget.blockSpacing),
      ],
    ];
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blockChildren,
      ),
    );
  }
}

class _BlockRenderHost extends StatefulWidget {
  const _BlockRenderHost({
    super.key,
    required this.signature,
    required this.node,
    required this.linkReferences,
    required this.footnoteNumbers,
    required this.builder,
  });

  final String signature;
  final MarkdownRenderNode node;
  final Map<String, String> linkReferences;
  final Map<String, int> footnoteNumbers;
  final _BlockBuilder builder;

  @override
  State<_BlockRenderHost> createState() => _BlockRenderHostState();
}

class _RevealScheduleScope extends InheritedWidget {
  const _RevealScheduleScope({
    required super.child,
    required this.revealedAt,
    required this.tokenArrivalDelay,
  });

  final DateTime? revealedAt;
  final Duration tokenArrivalDelay;

  static _RevealScheduleScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_RevealScheduleScope>();
  }

  @override
  bool updateShouldNotify(_RevealScheduleScope oldWidget) {
    return oldWidget.revealedAt != revealedAt ||
        oldWidget.tokenArrivalDelay != tokenArrivalDelay;
  }
}

class _BlockRenderHostState extends State<_BlockRenderHost>
    with AutomaticKeepAliveClientMixin<_BlockRenderHost> {
  String? _cachedSignature;
  Widget? _cachedChild;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _BlockRenderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      _cachedSignature = null;
      _cachedChild = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cachedChild == null || _cachedSignature != widget.signature) {
      _cachedChild = widget.builder(
        context,
        widget.node,
        widget.linkReferences,
        widget.footnoteNumbers,
      );
      _cachedSignature = widget.signature;
    }
    return RepaintBoundary(child: _cachedChild!);
  }
}

class _FadeInTokenHost extends StatefulWidget {
  const _FadeInTokenHost({
    this.initialDelay = Duration.zero,
    this.scheduledStart,
    required this.duration,
    required this.curve,
    this.animationBuilder,
    required this.child,
    super.key,
  });

  final Duration initialDelay;
  final DateTime? scheduledStart;
  final Duration duration;
  final Curve curve;
  final StreamingMarkdownTokenAnimationBuilder? animationBuilder;
  final Widget child;

  @override
  State<_FadeInTokenHost> createState() => _FadeInTokenHostState();
}

class _FadeInTokenHostState extends State<_FadeInTokenHost> {
  bool _revealed = false;
  bool _animationCompleted = false;
  Duration _animationDuration = Duration.zero;
  double _beginOpacity = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _configureSchedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _configureSchedule() {
    if (widget.duration <= Duration.zero) {
      _revealed = true;
      _animationCompleted = true;
      _animationDuration = Duration.zero;
      _beginOpacity = 1;
      return;
    }

    final DateTime now = DateTime.now();
    final Duration sanitizedDelay = widget.initialDelay <= Duration.zero
        ? Duration.zero
        : widget.initialDelay;
    final DateTime scheduledStart =
        widget.scheduledStart ?? now.add(sanitizedDelay);
    final DateTime scheduledEnd = scheduledStart.add(widget.duration);

    if (now.isBefore(scheduledStart)) {
      _revealed = false;
      _animationCompleted = false;
      _animationDuration = widget.duration;
      _beginOpacity = 0;
      _timer = Timer(scheduledStart.difference(now), _startAnimationNow);
      return;
    }

    if (!now.isBefore(scheduledEnd)) {
      _revealed = true;
      _animationCompleted = true;
      _animationDuration = Duration.zero;
      _beginOpacity = 1;
      return;
    }

    final Duration elapsed = now.difference(scheduledStart);
    final int totalMicros = widget.duration.inMicroseconds;
    final double progress =
        totalMicros <= 0 ? 1 : elapsed.inMicroseconds / totalMicros;
    _revealed = true;
    _animationCompleted = false;
    _animationDuration = scheduledEnd.difference(now);
    _beginOpacity = progress.clamp(0, 1).toDouble();
  }

  void _startAnimationNow() {
    if (!mounted) {
      return;
    }
    setState(() {
      _revealed = true;
      _animationCompleted = false;
      _animationDuration = widget.duration;
      _beginOpacity = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duration <= Duration.zero) {
      return widget.child;
    }
    if (!_revealed) {
      return const Offstage(offstage: true);
    }
    if (_animationCompleted || _animationDuration <= Duration.zero) {
      return widget.child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _beginOpacity, end: 1),
      duration: _animationDuration,
      curve: widget.curve,
      child: widget.child,
      onEnd: () {
        if (!mounted || _animationCompleted) {
          return;
        }
        setState(() {
          _animationCompleted = true;
        });
      },
      builder: (BuildContext context, double opacity, Widget? child) {
        final StreamingMarkdownTokenAnimationBuilder? builder =
            widget.animationBuilder;
        final Widget resolvedChild = child ?? widget.child;
        if (builder == null) {
          return Opacity(opacity: opacity, child: resolvedChild);
        }
        return builder(
          context,
          StreamingMarkdownAnimatedToken(
            child: resolvedChild,
            animation: AlwaysStoppedAnimation<double>(opacity),
          ),
        );
      },
    );
  }
}

class _HtmlBlockCard extends StatelessWidget {
  const _HtmlBlockCard({
    required this.html,
    required this.onLinkTap,
    required this.paragraphTextStyle,
  });

  final String html;
  final ValueChanged<String> onLinkTap;
  final TextStyle? paragraphTextStyle;

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final html_dom.DocumentFragment fragment = html_parser.parseFragment(html);
    final _HtmlBlockRenderer renderer = _HtmlBlockRenderer(
      context: context,
      onLinkTap: onLinkTap,
      paragraphTextStyle: paragraphTextStyle,
    );
    final List<Widget> blocks = renderer.buildBlocks(fragment.nodes);
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _HtmlBlockRenderer.withSpacing(blocks, 8),
      ),
    );
  }
}

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

  Widget _buildHeading(html_dom.Element element, {required int level}) {
    final double size;
    switch (level) {
      case 1:
        size = 26;
        break;
      case 2:
        size = 22;
        break;
      case 3:
        size = 20;
        break;
      case 4:
        size = 18;
        break;
      case 5:
        size = 16;
        break;
      default:
        size = 14;
        break;
    }
    return _buildParagraph(
      element.nodes,
      style:
          _paragraphStyle.copyWith(fontSize: size, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildParagraphFromText(String rawText) {
    final String normalized = _normalizeInlineText(rawText).trim();
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(normalized, style: _paragraphStyle);
  }

  Widget _buildParagraph(List<html_dom.Node> nodes, {TextStyle? style}) {
    final TextStyle resolvedStyle = style ?? _paragraphStyle;
    final List<InlineSpan> spans = _buildInlineSpans(nodes, resolvedStyle);
    final String plain =
        spans.map((InlineSpan span) => span.toPlainText()).join();
    if (plain.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Text.rich(TextSpan(style: resolvedStyle, children: spans));
  }

  Widget _buildCodeBlock(String raw) {
    final String code = raw.trimRight();
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: _codeBackgroundColor,
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          code,
          style: const TextStyle(
            color: _codeForegroundColor,
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildBlockQuote(html_dom.Element element, {required int listDepth}) {
    final List<Widget> blocks =
        buildBlocks(element.nodes, listDepth: listDepth);
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromRGBO(22, 27, 34, 0.35),
        border: const Border(left: BorderSide(color: _borderColor, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: withSpacing(blocks, 6),
      ),
    );
  }

  Widget _buildList(
    html_dom.Element element, {
    required bool ordered,
    required int listDepth,
  }) {
    final List<html_dom.Element> items = element.children
        .where((html_dom.Element child) => child.localName == 'li')
        .toList(growable: false);
    if (items.isEmpty) {
      return _buildParagraph(element.nodes);
    }

    final double markerWidth = 28 + (listDepth * 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: markerWidth,
                child: Text(
                  ordered ? '${i + 1}.' : '•',
                  style: _paragraphStyle,
                ),
              ),
              Expanded(
                child: _buildListItemBody(
                  items[i],
                  nextListDepth: listDepth + 1,
                ),
              ),
            ],
          ),
          if (i < items.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildListItemBody(html_dom.Element item,
      {required int nextListDepth}) {
    final List<Widget> blocks =
        buildBlocks(item.nodes, listDepth: nextListDepth);
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    if (blocks.length == 1) {
      return blocks.first;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: withSpacing(blocks, 6),
    );
  }

  Widget _buildTable(html_dom.Element table) {
    final List<html_dom.Element> rows = table.querySelectorAll('tr');
    if (rows.isEmpty) {
      return _buildParagraph(table.nodes);
    }

    final List<List<html_dom.Element>> matrix = <List<html_dom.Element>>[];
    int maxColumns = 0;
    for (final html_dom.Element row in rows) {
      final List<html_dom.Element> cells = row.children
          .where(
            (html_dom.Element child) =>
                child.localName == 'th' || child.localName == 'td',
          )
          .toList(growable: false);
      if (cells.isEmpty) {
        continue;
      }
      matrix.add(cells);
      if (cells.length > maxColumns) {
        maxColumns = cells.length;
      }
    }

    if (matrix.isEmpty || maxColumns == 0) {
      return _buildParagraph(table.nodes);
    }

    final List<TableRow> rowsOut = <TableRow>[];
    for (int rowIndex = 0; rowIndex < matrix.length; rowIndex++) {
      final List<html_dom.Element> row = matrix[rowIndex];
      final List<Widget> cellWidgets = <Widget>[];
      bool headerRow = rowIndex == 0;
      for (int col = 0; col < maxColumns; col++) {
        if (col >= row.length) {
          cellWidgets.add(_buildTableCell(const SizedBox.shrink()));
          continue;
        }
        final html_dom.Element cell = row[col];
        final bool isHeader = cell.localName == 'th' || rowIndex == 0;
        headerRow = headerRow || cell.localName == 'th';
        cellWidgets.add(
          _buildTableCell(
            _buildParagraph(
              cell.nodes,
              style: isHeader
                  ? _paragraphStyle.copyWith(fontWeight: FontWeight.w600)
                  : _paragraphStyle,
            ),
          ),
        );
      }
      rowsOut.add(
        TableRow(
          decoration:
              headerRow ? const BoxDecoration(color: Color(0x1A8B949E)) : null,
          children: cellWidgets,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        border: TableBorder.all(color: _borderColor),
        children: rowsOut,
      ),
    );
  }

  Widget _buildTableCell(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 88),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: child,
      ),
    );
  }

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
          color: _codeBackgroundColor,
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
          color: _linkColor,
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
                color: _codeForegroundColor,
                backgroundColor: _codeBackgroundColor,
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
              color: _linkColor,
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
      if (_blockTags.contains((node.localName ?? '').toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String _normalizeInlineText(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ');
  }
}
