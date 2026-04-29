part of '../view.dart';

extension _HtmlBlockRendererBlocks on _HtmlBlockRenderer {
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
        color: _HtmlBlockRenderer._codeBackgroundColor,
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          code,
          style: const TextStyle(
            color: _HtmlBlockRenderer._codeForegroundColor,
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
        border: const Border(
            left: BorderSide(color: _HtmlBlockRenderer._borderColor, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _HtmlBlockRenderer.withSpacing(blocks, 6),
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
      children: _HtmlBlockRenderer.withSpacing(blocks, 6),
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
        border: TableBorder.all(color: _HtmlBlockRenderer._borderColor),
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
}
