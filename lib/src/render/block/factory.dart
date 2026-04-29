part of '../view.dart';

extension _StreamingMarkdownBlockFactory on StreamingMarkdownRenderView {
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
        if (_parseFootnoteDefinitions(normalizedRaw).isNotEmpty) {
          return _buildFootnoteDefinitionBlock(
            context,
            node,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          );
        }
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
        return _buildCodeBlock(context, node);
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
        return _buildTableBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'pipe_table_delimiter_row':
        return const SizedBox.shrink();
      case 'html_block':
        return _HtmlBlockCard(
          html: _normalizedRaw(node.raw),
          onLinkTap: (String url) => _onLinkPressed(context, url),
          paragraphTextStyle: markdownTheme.paragraphTextStyle ??
              Theme.of(context).textTheme.bodyLarge,
        );
      case 'front_matter':
        return _buildMetadataBlock(
          context,
          node,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
      case 'link_reference_definition':
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

    final String normalizedParagraph = text.replaceAll('\n', ' ');

    final _InlineImageMatch? image =
        _matchSingleInlineImage(normalizedParagraph);
    if (image != null) {
      return _buildImageBlock(context, image);
    }

    return _buildInlineMarkdown(
      context,
      normalizedParagraph,
      baseStyle: markdownTheme.paragraphTextStyle ??
          Theme.of(context).textTheme.bodyLarge,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
  }
}
