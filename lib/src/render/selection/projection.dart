part of '../view.dart';

extension _StreamingMarkdownSelectionProjectionBuilder
    on StreamingMarkdownRenderView {
  _MarkdownSelectionProjection _buildSelectionProjection(
    List<MarkdownRenderNode> blocks, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final List<_MarkdownSelectionSegment> segments =
        <_MarkdownSelectionSegment>[];
    for (final MarkdownRenderNode block in blocks) {
      final String raw = _normalizedRaw(block.raw);
      switch (block.type) {
        case 'atx_heading':
        case 'setext_heading':
          segments.add(
            _MarkdownSelectionSegment.plain(
              plainText: _headingText(block),
              markdownText: raw,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'paragraph':
          segments.add(
            _inlineSelectionSegment(
              _paragraphText(block).replaceAll('\n', ' '),
              markdownText: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
          break;
        case 'list':
          segments.add(
            _listSelectionSegment(
              block,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
          break;
        case 'block_quote':
          segments.add(_quoteSelectionSegment(block));
          break;
        case 'fenced_code_block':
        case 'indented_code_block':
          segments.add(_codeBlockSelectionSegment(block));
          break;
        case 'footnote_definition':
        case 'link_reference_definition':
          final List<_FootnoteDefinition> definitions =
              _parseFootnoteDefinitions(raw);
          segments.add(
            _MarkdownSelectionSegment.plain(
              plainText: definitions.isEmpty
                  ? raw
                  : definitions
                      .map(
                        (_FootnoteDefinition definition) =>
                            '${definition.id}: ${definition.body}',
                      )
                      .join('\n'),
              markdownText: raw,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'html_block':
          segments.add(
            _MarkdownSelectionSegment.plain(
              plainText: _htmlBlockSelectionText(raw),
              markdownText: raw,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'thematic_break':
        case 'pipe_table_delimiter_row':
          segments.add(
            _MarkdownSelectionSegment.plain(
              plainText: '',
              markdownText: raw,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'pipe_table':
        case 'table':
          segments.add(_tableSelectionSegment(
            raw,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          ));
          break;
        default:
          segments.add(
            _MarkdownSelectionSegment.plain(
              plainText: _contentOrRaw(block),
              markdownText: raw,
            ),
          );
          break;
      }
    }
    return _MarkdownSelectionProjection(segments);
  }

  _MarkdownSelectionSegment _tableSelectionSegment(
    String raw, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _ParsedTable? table = _parseMarkdownTable(
      raw,
      allowLooseWithoutDelimiter: true,
      minLooseRowsWithoutDelimiter: 2,
    );
    if (table == null) {
      return _MarkdownSelectionSegment.plain(
        plainText: raw,
        markdownText: raw,
        preserveBlockMarkdownOnPartial: true,
      );
    }

    final List<_TableSelectionCell> cells = <_TableSelectionCell>[];
    int cursor = 0;
    void appendCell({
      required int rowIndex,
      required int columnIndex,
      required String markdown,
    }) {
      final _MarkdownSelectionSegment segment = _inlineSelectionSegment(
        markdown,
        markdownText: markdown,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
      final int start = cursor;
      cursor += segment.plainText.length;
      cells.add(
        _TableSelectionCell(
          rowIndex: rowIndex,
          columnIndex: columnIndex,
          segment: segment,
          start: start,
          end: cursor,
        ),
      );
    }

    for (int columnIndex = 0;
        columnIndex < table.headers.length;
        columnIndex++) {
      appendCell(
        rowIndex: 0,
        columnIndex: columnIndex,
        markdown: table.headers[columnIndex],
      );
    }
    for (int rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final List<String> row = table.rows[rowIndex];
      for (int columnIndex = 0; columnIndex < row.length; columnIndex++) {
        appendCell(
          rowIndex: rowIndex + 1,
          columnIndex: columnIndex,
          markdown: row[columnIndex],
        );
      }
    }

    final String plainText =
        cells.map((_TableSelectionCell cell) => cell.segment.plainText).join();
    return _MarkdownSelectionSegment(
      pieces: <_MarkdownSelectionPiece>[
        _MarkdownSelectionPiece(plainText: plainText, markdownText: raw),
      ],
      fallbackMarkdownText: raw,
      rangeMarkdownBuilder: (int selectionStart, int selectionEnd) {
        return _markdownTableForPlainRange(
          table: table,
          cells: cells,
          selectionStart: selectionStart,
          selectionEnd: selectionEnd,
        );
      },
    );
  }
}
