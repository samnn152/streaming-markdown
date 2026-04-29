part of '../view.dart';

extension _SequencedBlockTokenCounting on _SequencedBlockListState {
  Duration _nextDequeueDelayAfterReveal(MarkdownRenderNode? node) {
    if (widget.tokenArrivalDelay <= Duration.zero || node == null) {
      return Duration.zero;
    }
    final int tokens = _tokenCountForNode(node);
    if (tokens <= 0) {
      return Duration.zero;
    }
    if (node.type == 'fenced_code_block' ||
        node.type == 'indented_code_block') {
      // Avoid long pauses after big code blocks.
      return widget.tokenArrivalDelay * 8;
    }
    if (tokens <= 1) {
      return widget.tokenArrivalDelay;
    }
    return widget.tokenArrivalDelay * tokens;
  }

  int _tokenCountForNode(MarkdownRenderNode node) {
    if (_isDelimiterNode(node.type)) {
      return 0;
    }
    if (_isTableNode(node.type)) {
      return _tableContentTokenCount(node);
    }
    final String text =
        (node.content.isNotEmpty ? node.content : node.raw).trim();
    if (text.isEmpty) {
      return 1;
    }
    final int count = RegExp(r'\S+').allMatches(text).length;
    return count <= 0 ? 1 : count;
  }

  bool _isDelimiterNode(String type) {
    return type == 'thematic_break' || type == 'pipe_table_delimiter_row';
  }

  bool _isTableNode(String type) {
    return type == 'pipe_table' ||
        type == 'table' ||
        type == 'pipe_table_header' ||
        type == 'pipe_table_row' ||
        type == 'pipe_table_delimiter_row';
  }

  int _tableContentTokenCount(MarkdownRenderNode node) {
    int total = 0;
    bool started = false;
    for (final String original in node.raw.replaceAll('\r', '').split('\n')) {
      final String line = original.trimRight();
      if (line.trim().isEmpty) {
        if (started) {
          break;
        }
        continue;
      }
      if (!line.contains('|')) {
        if (started) {
          break;
        }
        continue;
      }
      started = true;
      if (_isTableDelimiterLine(line)) {
        continue;
      }
      for (final String cell in _splitSimpleTableLine(line)) {
        total += RegExp(r'\S+').allMatches(cell).length;
      }
    }
    return total;
  }

  bool _isTableDelimiterLine(String line) {
    final List<String> cells = _splitSimpleTableLine(line);
    if (cells.isEmpty) {
      return false;
    }
    for (final String cell in cells) {
      if (!RegExp(r'^:?-+:?$').hasMatch(cell.replaceAll(' ', ''))) {
        return false;
      }
    }
    return true;
  }

  List<String> _splitSimpleTableLine(String line) {
    final String value = line.trim();
    if (!value.contains('|')) {
      return <String>[];
    }
    final List<String> cells =
        value.split('|').map((String cell) => cell.trim()).toList();
    if (value.startsWith('|') && cells.isNotEmpty && cells.first.isEmpty) {
      cells.removeAt(0);
    }
    if (value.endsWith('|') && cells.isNotEmpty && cells.last.isEmpty) {
      cells.removeLast();
    }
    return cells.where((String cell) => cell.isNotEmpty).toList();
  }
}
