part of '../view.dart';

class _MarkdownSelectionSegmentRange {
  const _MarkdownSelectionSegmentRange({
    required this.segment,
    required this.start,
    required this.end,
  });

  final _MarkdownSelectionSegment segment;
  final int start;
  final int end;
}

class _MarkdownSelectionSegment {
  const _MarkdownSelectionSegment({
    required this.pieces,
    required this.fallbackMarkdownText,
    this.preserveBlockMarkdownOnPartial = false,
    this.rangeMarkdownBuilder,
  });

  factory _MarkdownSelectionSegment.plain({
    required String plainText,
    required String markdownText,
    bool preserveBlockMarkdownOnPartial = false,
  }) {
    return _MarkdownSelectionSegment(
      pieces: <_MarkdownSelectionPiece>[
        _MarkdownSelectionPiece(
            plainText: plainText, markdownText: markdownText),
      ],
      fallbackMarkdownText: markdownText,
      preserveBlockMarkdownOnPartial: preserveBlockMarkdownOnPartial,
    );
  }

  final List<_MarkdownSelectionPiece> pieces;
  final String fallbackMarkdownText;
  final bool preserveBlockMarkdownOnPartial;
  final String Function(int selectionStart, int selectionEnd)?
      rangeMarkdownBuilder;

  String get plainText {
    final StringBuffer buffer = StringBuffer();
    for (final _MarkdownSelectionPiece piece in pieces) {
      buffer.write(piece.plainText);
    }
    return buffer.toString();
  }

  String get markdownText => fallbackMarkdownText;

  String markdownForPlainText(String selectedPlainText) {
    if (selectedPlainText == plainText) {
      return fallbackMarkdownText;
    }
    final int selectionStart = plainText.indexOf(selectedPlainText);
    if (selectionStart < 0) {
      return '';
    }
    return markdownForPlainRange(
      selectionStart,
      selectionStart + selectedPlainText.length,
    );
  }

  String markdownForPlainRange(int selectionStart, int selectionEnd) {
    if (selectionStart <= 0 && selectionEnd >= plainText.length) {
      return fallbackMarkdownText;
    }
    final String Function(int selectionStart, int selectionEnd)? builder =
        rangeMarkdownBuilder;
    if (builder != null) {
      return builder(
        selectionStart.clamp(0, plainText.length),
        selectionEnd.clamp(0, plainText.length),
      );
    }
    if (preserveBlockMarkdownOnPartial &&
        selectionStart < plainText.length &&
        selectionEnd > 0) {
      return fallbackMarkdownText;
    }

    int cursor = 0;
    final StringBuffer out = StringBuffer();
    bool hasMatch = false;
    for (final _MarkdownSelectionPiece piece in pieces) {
      final int start = cursor;
      final int end = start + piece.plainText.length;
      cursor = end;

      if (selectionEnd <= start || selectionStart >= end) {
        continue;
      }
      if (selectionStart <= start && selectionEnd >= end) {
        out.write(piece.markdownText);
        hasMatch = true;
      } else {
        final int localStart =
            (selectionStart - start).clamp(0, piece.plainText.length);
        final int localEnd =
            (selectionEnd - start).clamp(0, piece.plainText.length);
        out.write(
          _slicePieceMarkdown(
            piece: piece,
            localStart: localStart,
            localEnd: localEnd,
          ),
        );
        hasMatch = true;
      }
    }
    return hasMatch ? out.toString() : '';
  }

  String _slicePieceMarkdown({
    required _MarkdownSelectionPiece piece,
    required int localStart,
    required int localEnd,
  }) {
    final String plain = piece.plainText;
    final String markdown = piece.markdownText;
    if (plain.isEmpty || localStart >= localEnd) {
      return '';
    }
    if (markdown == plain) {
      return plain.substring(localStart, localEnd);
    }
    final int plainIndex = markdown.indexOf(plain);
    if (plainIndex < 0) {
      return plain.substring(localStart, localEnd);
    }
    final String prefix = markdown.substring(0, plainIndex);
    final String suffix = markdown.substring(plainIndex + plain.length);
    if (prefix == '[' && suffix.startsWith('](')) {
      return '$prefix${plain.substring(localStart, localEnd)}$suffix';
    }
    final StringBuffer out = StringBuffer();
    if (localStart > 0) {
      out.write(prefix);
    }
    out.write(plain.substring(localStart, localEnd));
    if (localEnd < plain.length) {
      out.write(suffix);
    }
    return out.toString();
  }
}

class _MarkdownSelectionPiece {
  const _MarkdownSelectionPiece({
    required this.plainText,
    required this.markdownText,
  });

  final String plainText;
  final String markdownText;
}

class _TableSelectionCell {
  const _TableSelectionCell({
    required this.rowIndex,
    required this.columnIndex,
    required this.segment,
    required this.start,
    required this.end,
  });

  final int rowIndex;
  final int columnIndex;
  final _MarkdownSelectionSegment segment;
  final int start;
  final int end;
}

class _ListSelectionItem {
  const _ListSelectionItem({
    required this.item,
    required this.segment,
    required this.start,
    required this.end,
  });

  final _ParsedListItem item;
  final _MarkdownSelectionSegment segment;
  final int start;
  final int end;
}
