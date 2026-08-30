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
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenArrivalDelay;
    final Color borderColor = markdownTheme.tableBorderColor ??
        Color.alphaBlend(
          _markdownColorWithAlpha(colorScheme.outline, 0.18),
          colorScheme.outlineVariant,
        );
    final Color headerBackground = markdownTheme.tableHeaderBackgroundColor ??
        Color.alphaBlend(
          _markdownColorWithAlpha(colorScheme.primary, 0.08),
          _markdownSurfaceContainerHighest(colorScheme),
        );
    final Color bodyBackground = Color.alphaBlend(
      _markdownColorWithAlpha(colorScheme.surface, 0.92),
      _markdownSurfaceContainerLowest(colorScheme),
    );
    final Color alternateRowBackground = Color.alphaBlend(
      _markdownColorWithAlpha(
        _markdownSurfaceContainerLow(colorScheme),
        0.72,
      ),
      colorScheme.surface,
    );

    if (!_tableHasRenderableCell(table)) {
      return const SizedBox(key: ValueKey<String>('markdown_table_frame'));
    }

    final List<double> columnWidths = _tableColumnWidths(context, table);
    final double tableWidth = columnWidths.fold<double>(
      0,
      (double sum, double width) => sum + width,
    );
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double viewportMaxWidth = screenWidth >= 900 ? 560 : screenWidth;
    final double frameWidth =
        tableWidth < viewportMaxWidth ? tableWidth : viewportMaxWidth;
    final List<List<String>> visualRows = <List<String>>[
      table.headers,
      ...table.rows,
    ];
    final List<List<int>> plainTextStarts = List<List<int>>.generate(
      visualRows.length,
      (_) => List<int>.filled(table.headers.length, 0),
    );
    int plainCursor = 0;
    for (int rowIndex = 0; rowIndex < visualRows.length; rowIndex++) {
      for (int col = 0; col < table.headers.length; col++) {
        final List<String> row = visualRows[rowIndex];
        final String cell = col < row.length ? row[col] : '';
        final String cellPlainText = _inlineSelectionPlainText(
          cell,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        );
        plainCursor += cellPlainText.length;
        plainTextStarts[rowIndex][col] = plainCursor - cellPlainText.length;
      }
    }

    final SelectionRegistrar? tableRegistrar =
        enableTextSelection ? SelectionContainer.maybeOf(context) : null;

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        key: const ValueKey<String>('markdown_table_frame'),
        width: frameWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(color: bodyBackground),
          child: _MarkdownSelectionAutoScrollRegionHost(
            axis: Axis.horizontal,
            builder: (
              BuildContext context,
              ScrollController scrollController,
            ) {
              return SelectionContainer.disabled(
                child: SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: _MarkdownSelectionScrollableRegistration(
                    child: Builder(
                      builder: (BuildContext tableContext) {
                        final List<Widget> rowTables = _buildTableRows(
                          tableContext,
                          table: table,
                          theme: theme,
                          colorScheme: colorScheme,
                          headerBackground: headerBackground,
                          bodyBackground: bodyBackground,
                          alternateRowBackground: alternateRowBackground,
                          borderColor: borderColor,
                          columnWidths: columnWidths,
                          tableWidth: tableWidth,
                          tokenScheduleOrigin: tokenScheduleOrigin,
                          resolvedTokenStep: resolvedTokenStep,
                          linkReferences: linkReferences,
                          footnoteNumbers: footnoteNumbers,
                          plainTextStarts: plainTextStarts,
                          tableRegistrar: tableRegistrar,
                        );
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: tableWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: rowTables,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTableRows(
    BuildContext context, {
    required _ParsedTable table,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Color headerBackground,
    required Color bodyBackground,
    required Color alternateRowBackground,
    required Color borderColor,
    required List<double> columnWidths,
    required double tableWidth,
    required DateTime? tokenScheduleOrigin,
    required Duration resolvedTokenStep,
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
    required List<List<int>> plainTextStarts,
    SelectionRegistrar? tableRegistrar,
  }) {
    Widget buildStableCellContent({
      required String cell,
      required int tokenStartIndex,
      required int plainTextStart,
      required TextStyle baseStyle,
    }) {
      return _TokenReserveLayoutScope(
        enabled: true,
        child: _buildInlineMarkdown(
          context,
          cell,
          tokenStartIndex: tokenStartIndex,
          plainTextStart: plainTextStart,
          restrictSelectionToRevealedTokens: true,
          baseStyle: baseStyle,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
          customRegistrar: tableRegistrar,
        ),
      );
    }

    Widget buildCellPadding({
      required String cell,
      required int tokenStartIndex,
      required int plainTextStart,
      required TextStyle baseStyle,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: buildStableCellContent(
          cell: cell,
          tokenStartIndex: tokenStartIndex,
          plainTextStart: plainTextStart,
          baseStyle: baseStyle,
        ),
      );
    }

    Widget buildRow({
      required List<String> cells,
      required int rowTokenStartIndex,
      required List<int> rowPlainTextStarts,
      required bool isHeader,
      required int bodyRowIndex,
      required bool revealWithGate,
      required int rowIndex,
    }) {
      int localTokenIndex = rowTokenStartIndex;
      final List<Widget> children = <Widget>[];
      for (int col = 0; col < table.headers.length; col++) {
        final String cell = col < cells.length ? cells[col] : '';
        final int tokenUnits = _countAnimatedTokenUnits(
          cell,
          linkReferences: linkReferences,
        );
        children.add(
          SizedBox(
            width: columnWidths[col],
            child: buildCellPadding(
              cell: cell,
              tokenStartIndex: localTokenIndex,
              plainTextStart: rowPlainTextStarts[col],
              baseStyle: isHeader
                  ? theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ) ??
                      TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      )
                  : theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ) ??
                      TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
            ),
          ),
        );
        localTokenIndex += tokenUnits;
      }

      final Widget rowWidget = SizedBox(
        key: ValueKey<String>('markdown_table_row_$rowIndex'),
        width: tableWidth,
        child: ColoredBox(
          color: isHeader
              ? headerBackground
              : (bodyRowIndex.isEven ? bodyBackground : alternateRowBackground),
          child: Table(
            border: TableBorder(
              top: isHeader ? BorderSide(color: borderColor) : BorderSide.none,
              bottom: BorderSide(color: borderColor),
              left: BorderSide(color: borderColor),
              right: BorderSide(color: borderColor),
              verticalInside: BorderSide(color: borderColor),
            ),
            columnWidths: <int, TableColumnWidth>{
              for (int col = 0; col < columnWidths.length; col++)
                col: FixedColumnWidth(columnWidths[col]),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: <TableRow>[
              TableRow(children: children),
            ],
          ),
        ),
      );

      if (!revealWithGate) {
        return rowWidget;
      }

      return _TokenLayoutGate(
        initialDelay: tokenScheduleOrigin == null
            ? resolvedTokenStep * rowTokenStartIndex
            : Duration.zero,
        scheduledStart: tokenScheduleOrigin?.add(
          resolvedTokenStep * rowTokenStartIndex,
        ),
        child: rowWidget,
      );
    }

    int tokenStartIndex = 0;
    final int headerGateStartIndex = tokenStartIndex;
    for (int col = 0; col < table.headers.length; col++) {
      tokenStartIndex += _countAnimatedTokenUnits(
        table.headers[col],
        linkReferences: linkReferences,
      );
    }

    final List<Widget> rowTables = <Widget>[
      buildRow(
        cells: table.headers,
        rowTokenStartIndex: headerGateStartIndex,
        rowPlainTextStarts: plainTextStarts[0],
        isHeader: true,
        bodyRowIndex: 0,
        revealWithGate: false,
        rowIndex: 0,
      ),
    ];
    for (int rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final List<String> row = table.rows[rowIndex];
      final int rowGateStartIndex = tokenStartIndex;
      for (int col = 0; col < row.length; col++) {
        tokenStartIndex += _countAnimatedTokenUnits(
          row[col],
          linkReferences: linkReferences,
        );
      }
      rowTables.add(
        buildRow(
          cells: row,
          rowTokenStartIndex: rowGateStartIndex,
          rowPlainTextStarts: plainTextStarts[rowIndex + 1],
          isHeader: false,
          bodyRowIndex: rowIndex,
          revealWithGate: true,
          rowIndex: rowIndex + 1,
        ),
      );
    }
    return rowTables;
  }

  List<double> _tableColumnWidths(
    BuildContext context,
    _ParsedTable table,
  ) {
    final int columnCount = table.headers.length;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double viewportMaxWidth = screenWidth >= 900 ? 560 : screenWidth;
    const double horizontalPaddingPerCell = 28;
    final List<double> preferredWidths =
        List<double>.filled(columnCount, 112, growable: false);

    for (int col = 0; col < columnCount; col++) {
      double maxWidth = _estimatedTableCellWidth(table.headers[col]) +
          horizontalPaddingPerCell;
      for (final List<String> row in table.rows) {
        if (col >= row.length) {
          continue;
        }
        final double rowWidth =
            _estimatedTableCellWidth(row[col]) + horizontalPaddingPerCell;
        if (rowWidth > maxWidth) {
          maxWidth = rowWidth;
        }
      }
      preferredWidths[col] = maxWidth.clamp(112, 360);
    }

    final double totalPreferred = preferredWidths.fold<double>(
      0,
      (double sum, double width) => sum + width,
    );
    final double targetWidth = viewportMaxWidth.clamp(320, 560);
    final bool shouldScaleDown = totalPreferred > targetWidth;
    final double scale = shouldScaleDown ? targetWidth / totalPreferred : 1;
    return List<double>.generate(columnCount, (int col) {
      final double scaledWidth =
          shouldScaleDown ? preferredWidths[col] * scale : preferredWidths[col];
      return scaledWidth.clamp(112, preferredWidths[col]);
    }, growable: false);
  }

  double _estimatedTableCellWidth(String markdown) {
    final String plain = markdown
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), 'img')
        .replaceAll(RegExp(r'\[[^\]]+\]\([^)]+\)'), 'link')
        .replaceAll(RegExp(r'[`*_~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isEmpty) {
      return 96;
    }

    final List<String> words = plain.split(' ');
    int longestWord = 0;
    for (final String word in words) {
      if (word.length > longestWord) {
        longestWord = word.length;
      }
    }
    final int visibleChars = plain.length > 42 ? 42 : plain.length;
    final double contentWidth = visibleChars * 7.6;
    final double longestWordWidth = longestWord * 8.4;
    final double estimated =
        contentWidth > longestWordWidth ? contentWidth : longestWordWidth;
    return estimated.clamp(96, 332);
  }

  bool _tableHasRenderableCell(_ParsedTable table) {
    for (final String cell in table.headers) {
      if (cell.trim().isNotEmpty) {
        return true;
      }
    }
    for (final List<String> row in table.rows) {
      for (final String cell in row) {
        if (cell.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }
}

Color _markdownColorWithAlpha(Color color, double alpha) {
  final dynamic dynamicColor = color;
  try {
    // Color.withValues preserves wide-gamut channels on recent Flutter SDKs.
    return dynamicColor.withValues(alpha: alpha) as Color;
  } on NoSuchMethodError {
    // Flutter 3.10 exposes only Color.withOpacity.
    return dynamicColor.withOpacity(alpha) as Color;
  }
}

Color _markdownSurfaceContainerHighest(ColorScheme colorScheme) {
  final dynamic dynamicScheme = colorScheme;
  try {
    return dynamicScheme.surfaceContainerHighest as Color;
  } on NoSuchMethodError {
    return dynamicScheme.surfaceVariant as Color;
  }
}

Color _markdownSurfaceContainerLowest(ColorScheme colorScheme) {
  final dynamic dynamicScheme = colorScheme;
  try {
    return dynamicScheme.surfaceContainerLowest as Color;
  } on NoSuchMethodError {
    return colorScheme.surface;
  }
}

Color _markdownSurfaceContainerLow(ColorScheme colorScheme) {
  final dynamic dynamicScheme = colorScheme;
  try {
    return dynamicScheme.surfaceContainerLow as Color;
  } on NoSuchMethodError {
    return dynamicScheme.surfaceVariant as Color;
  }
}
