part of '../view.dart';

extension _StreamingMarkdownSelectionTableFormatting
    on StreamingMarkdownRenderView {
  String _markdownTableForPlainRange({
    required _ParsedTable table,
    required List<_TableSelectionCell> cells,
    required int selectionStart,
    required int selectionEnd,
  }) {
    final Map<int, String> selectedHeaders = <int, String>{};
    final Map<int, Map<int, String>> selectedRows = <int, Map<int, String>>{};
    final Set<int> selectedColumns = <int>{};

    for (final _TableSelectionCell cell in cells) {
      if (cell.segment.plainText.isEmpty ||
          selectionEnd <= cell.start ||
          selectionStart >= cell.end) {
        continue;
      }

      final int localStart =
          (selectionStart - cell.start).clamp(0, cell.segment.plainText.length);
      final int localEnd =
          (selectionEnd - cell.start).clamp(0, cell.segment.plainText.length);
      final String markdown = cell.segment.markdownForPlainRange(
        localStart,
        localEnd,
      );
      if (markdown.isEmpty) {
        continue;
      }

      selectedColumns.add(cell.columnIndex);
      if (cell.rowIndex == 0) {
        selectedHeaders[cell.columnIndex] = markdown;
      } else {
        selectedRows.putIfAbsent(
            cell.rowIndex, () => <int, String>{})[cell.columnIndex] = markdown;
      }
    }

    if (selectedColumns.isEmpty) {
      return '';
    }

    final List<int> columns = selectedColumns.toList()..sort();
    final List<String> headers = <String>[
      for (final int column in columns)
        selectedHeaders[column] ?? _tableSourceCell(table.headers, column),
    ];
    final List<List<String>> rows = <List<String>>[];
    final List<int> rowIndexes = selectedRows.keys.toList()..sort();
    for (final int rowIndex in rowIndexes) {
      final Map<int, String> selectedRow = selectedRows[rowIndex]!;
      rows.add(<String>[
        for (final int column in columns) selectedRow[column] ?? '',
      ]);
    }

    return _formatMarkdownTable(headers: headers, rows: rows);
  }

  String _tableSourceCell(List<String> cells, int index) {
    if (index < 0 || index >= cells.length) {
      return '';
    }
    return cells[index];
  }

  String _formatMarkdownTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    if (headers.isEmpty) {
      return '';
    }

    final StringBuffer out = StringBuffer();
    out.writeln(_formatMarkdownTableRow(headers));
    out.write(
      _formatMarkdownTableRow(List<String>.filled(headers.length, '---')),
    );
    for (final List<String> row in rows) {
      out.writeln();
      out.write(_formatMarkdownTableRow(row));
    }
    return out.toString();
  }

  String _formatMarkdownTableRow(List<String> cells) {
    return '| ${cells.map(_escapeMarkdownTableCell).join(' | ')} |';
  }

  String _escapeMarkdownTableCell(String markdown) {
    final StringBuffer out = StringBuffer();
    int codeFenceLength = 0;
    bool escaped = false;
    for (int i = 0; i < markdown.length; i++) {
      final String ch = markdown[i];
      if (escaped) {
        out.write(ch);
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        out.write(ch);
        escaped = true;
        continue;
      }
      if (ch == '`') {
        int runLength = 1;
        while (
            i + runLength < markdown.length && markdown[i + runLength] == '`') {
          runLength += 1;
        }
        if (codeFenceLength == 0) {
          codeFenceLength = runLength;
        } else if (runLength >= codeFenceLength) {
          codeFenceLength = 0;
        }
        out.write(markdown.substring(i, i + runLength));
        i += runLength - 1;
        continue;
      }
      if (ch == '|' && codeFenceLength == 0) {
        out.write(r'\|');
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }
}
