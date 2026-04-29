part of '../view.dart';

extension _StreamingMarkdownTableAndMetadataRenderer
    on StreamingMarkdownRenderView {
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
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenArrivalDelay;
    final Color borderColor =
        markdownTheme.tableBorderColor ?? const Color(0xFF30363D);
    final Color headerBackground =
        markdownTheme.tableHeaderBackgroundColor ?? const Color(0xFF21262D);

    Widget buildRevealedCell({
      required Widget child,
      required int tokenUnits,
      required int tokenStartIndex,
      required bool isFirstRow,
      required bool isFirstColumn,
      required bool isHeader,
    }) {
      final Widget cell = Container(
        decoration: BoxDecoration(
          color: isHeader ? headerBackground : null,
          border: Border(
            top: isFirstRow ? BorderSide(color: borderColor) : BorderSide.none,
            left: isFirstColumn
                ? BorderSide(color: borderColor)
                : BorderSide.none,
            right: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
        child: child,
      );

      if (tokenUnits <= 0) {
        return const SizedBox.shrink();
      }
      return _TokenLayoutGate(
        initialDelay: tokenScheduleOrigin == null
            ? resolvedTokenStep * tokenStartIndex
            : Duration.zero,
        scheduledStart: tokenScheduleOrigin?.add(
          resolvedTokenStep * tokenStartIndex,
        ),
        child: cell,
      );
    }

    int tokenStartIndex = 0;
    final List<TableRow> rows = <TableRow>[];

    final List<Widget> headerCells = <Widget>[];
    for (int col = 0; col < table.headers.length; col++) {
      final String cell = table.headers[col];
      final int tokenUnits = _countAnimatedTokenUnits(
        cell,
        linkReferences: linkReferences,
      );
      headerCells.add(
        buildRevealedCell(
          tokenStartIndex: tokenStartIndex,
          tokenUnits: tokenUnits,
          isFirstRow: true,
          isFirstColumn: col == 0,
          isHeader: true,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _buildInlineMarkdown(
              context,
              cell,
              tokenStartIndex: tokenStartIndex,
              baseStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          ),
        ),
      );
      tokenStartIndex += tokenUnits;
    }
    rows.add(
      TableRow(
        children: headerCells,
      ),
    );

    for (int rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final List<String> row = table.rows[rowIndex];
      final List<Widget> bodyCells = <Widget>[];
      for (int col = 0; col < row.length; col++) {
        final String cell = row[col];
        final int tokenUnits = _countAnimatedTokenUnits(
          cell,
          linkReferences: linkReferences,
        );
        bodyCells.add(
          buildRevealedCell(
            tokenStartIndex: tokenStartIndex,
            tokenUnits: tokenUnits,
            isFirstRow: false,
            isFirstColumn: col == 0,
            isHeader: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _buildInlineMarkdown(
                context,
                cell,
                tokenStartIndex: tokenStartIndex,
                baseStyle: const TextStyle(fontSize: 13),
                linkReferences: linkReferences,
                footnoteNumbers: footnoteNumbers,
              ),
            ),
          ),
        );
        tokenStartIndex += tokenUnits;
      }
      rows.add(TableRow(children: bodyCells));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );
  }
}
