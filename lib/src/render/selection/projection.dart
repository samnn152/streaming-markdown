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
      final String raw = _selectionRaw(block.raw);
      switch (block.type) {
        case 'atx_heading':
        case 'setext_heading':
          final String headingMarkdown = _headingText(block);
          segments.add(
            _embeddedInlineSelectionSegment(
              headingMarkdown,
              sourceMarkdown: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
              preserveBlockMarkdownOnPartial: true,
            ),
          );
          break;
        case 'paragraph':
          final List<_FootnoteDefinition> paragraphDefinitions =
              _parseFootnoteDefinitions(raw);
          if (paragraphDefinitions.isNotEmpty) {
            segments.add(
              _footnoteSelectionSegment(
                raw,
                paragraphDefinitions,
                linkReferences: linkReferences,
                footnoteNumbers: footnoteNumbers,
              ),
            );
            break;
          }
          _ParsedTable? paragraphTable = _parseMarkdownTable(raw);
          if (paragraphTable == null && raw.contains('\n')) {
            paragraphTable = _parseMarkdownTable(
              raw,
              allowLooseWithoutDelimiter: true,
              minLooseRowsWithoutDelimiter: 2,
            );
          }
          segments.add(
            paragraphTable == null
                ? _inlineSelectionSegment(
                    _selectionParagraphText(block),
                    markdownText: raw,
                    linkReferences: linkReferences,
                    footnoteNumbers: footnoteNumbers,
                  )
                : _tableSelectionSegment(
                    raw,
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
          segments.add(
            _quoteSelectionSegment(
              block,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
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
            definitions.isEmpty
                ? _inlineSelectionSegment(
                    raw,
                    markdownText: raw,
                    linkReferences: linkReferences,
                    footnoteNumbers: footnoteNumbers,
                  )
                : _footnoteSelectionSegment(
                    raw,
                    definitions,
                    linkReferences: linkReferences,
                    footnoteNumbers: footnoteNumbers,
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
        case 'front_matter':
          segments.add(
            _inlineSelectionSegment(
              raw,
              markdownText: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
          break;
        default:
          segments.add(
            _inlineSelectionSegment(
              _paragraphText(block),
              markdownText: raw,
              linkReferences: linkReferences,
              footnoteNumbers: footnoteNumbers,
            ),
          );
          break;
      }
    }
    return _MarkdownSelectionProjection(segments);
  }

  _MarkdownSelectionSegment _footnoteSelectionSegment(
    String raw,
    List<_FootnoteDefinition> definitions, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final String plainText = definitions.map((_FootnoteDefinition definition) {
      final String body = _inlineSelectionPlainText(
        definition.body,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
      return '${definition.id}: $body';
    }).join('\n');
    return _MarkdownSelectionSegment.plain(
      plainText: plainText,
      markdownText: raw,
      preserveBlockMarkdownOnPartial: true,
    );
  }

  String _selectionParagraphText(MarkdownRenderNode node) {
    final String raw = _selectionRaw(node.raw);
    if (raw.trim().isNotEmpty) {
      return raw.replaceAll('\n', ' ');
    }
    return node.content;
  }

  String _selectionRaw(String raw) {
    return raw.replaceAll('\r', '').replaceFirst(RegExp(r'\n+$'), '');
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

    void appendRow({
      required int rowIndex,
      required List<String> row,
    }) {
      for (int columnIndex = 0;
          columnIndex < table.headers.length;
          columnIndex++) {
        if (columnIndex >= row.length) {
          continue;
        }
        appendCell(
          rowIndex: rowIndex,
          columnIndex: columnIndex,
          markdown: row[columnIndex],
        );
      }
    }

    appendRow(rowIndex: 0, row: table.headers);
    for (int rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      appendRow(rowIndex: rowIndex + 1, row: table.rows[rowIndex]);
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
