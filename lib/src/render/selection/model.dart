part of '../view.dart';

class _MarkdownSelectionProjection {
  const _MarkdownSelectionProjection(this.segments);

  final List<_MarkdownSelectionSegment> segments;

  String get fullPlainText {
    final StringBuffer plain = StringBuffer();
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write('\n\n');
      }
      plain.write(segments[i].plainText);
    }
    return plain.toString();
  }

  String get compactPlainText {
    final StringBuffer plain = StringBuffer();
    for (final _MarkdownSelectionSegment segment in segments) {
      plain.write(segment.plainText);
    }
    return plain.toString();
  }

  String get fullMarkdownText {
    final StringBuffer markdown = StringBuffer();
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        markdown.write('\n\n');
      }
      markdown.write(segments[i].markdownText);
    }
    return markdown.toString();
  }

  int get _compactPlainTextLength {
    int length = 0;
    for (final _MarkdownSelectionSegment segment in segments) {
      length += segment.plainText.length;
    }
    return length;
  }

  _MarkdownSelectionRange? findRangeForSelectedPlainText(
    String selectedPlainText, {
    int? preferredStart,
  }) {
    final String selected = selectedPlainText.replaceAll('\r', '');
    if (selected.isEmpty) {
      return null;
    }
    final String document = fullPlainText;
    if (document.isEmpty || selected.length > document.length) {
      return null;
    }

    int bestStart = -1;
    int searchFrom = 0;
    while (searchFrom <= document.length) {
      final int hit = document.indexOf(selected, searchFrom);
      if (hit < 0) {
        break;
      }
      if (preferredStart == null) {
        bestStart = hit;
        break;
      }
      if (bestStart < 0 ||
          (hit - preferredStart).abs() < (bestStart - preferredStart).abs()) {
        bestStart = hit;
      }
      searchFrom = hit + 1;
    }
    if (bestStart < 0) {
      final _NormalizedDocumentSelectionMatch? displayMatch =
          _matchWhitespaceNormalizedSelection(
        selected,
        plainSeparator: '\n\n',
      );
      if (displayMatch != null) {
        return _MarkdownSelectionRange(
          start: displayMatch.selectionStart,
          end: displayMatch.selectionEnd,
        );
      }

      final _NormalizedDocumentSelectionMatch? compactMatch =
          _matchWhitespaceNormalizedSelection(
        selected,
        plainSeparator: '',
      );
      if (compactMatch != null) {
        return displayRangeForCompactRange(
          _MarkdownSelectionRange(
            start: compactMatch.selectionStart,
            end: compactMatch.selectionEnd,
          ),
        );
      }
      return null;
    }
    return _MarkdownSelectionRange(
      start: bestStart,
      end: bestStart + selected.length,
    );
  }

  String plainTextForRange(_MarkdownSelectionRange range) {
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    int cursor = 0;
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        cursor += 2;
      }
      final _MarkdownSelectionSegment segment = segments[i];
      final int start = cursor;
      cursor += segment.plainText.length;
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segment,
          start: start,
          end: cursor,
        ),
      );
    }

    final int selectionStart = range.start.clamp(0, cursor);
    final int selectionEnd = range.end.clamp(selectionStart, cursor);
    final StringBuffer out = StringBuffer();
    for (final _MarkdownSelectionSegmentRange segmentRange in ranges) {
      final _MarkdownSelectionSegment segment = segmentRange.segment;
      final bool isEmptySegment = segmentRange.start == segmentRange.end;
      final bool intersects = isEmptySegment
          ? selectionStart < segmentRange.start &&
              selectionEnd > segmentRange.start
          : selectionStart < segmentRange.end &&
              selectionEnd > segmentRange.start;
      if (!intersects) {
        continue;
      }
      final String piece = isEmptySegment
          ? ''
          : segment.plainText.substring(
              (selectionStart - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
              (selectionEnd - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (piece.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(piece);
    }
    return out.toString();
  }

  String markdownForRange(_MarkdownSelectionRange range) {
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    int cursor = 0;
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        cursor += 2;
      }
      final _MarkdownSelectionSegment segment = segments[i];
      final int start = cursor;
      cursor += segment.plainText.length;
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segment,
          start: start,
          end: cursor,
        ),
      );
    }

    final int selectionStart = range.start.clamp(0, cursor);
    final int selectionEnd = range.end.clamp(selectionStart, cursor);
    final StringBuffer out = StringBuffer();

    for (final _MarkdownSelectionSegmentRange segmentRange in ranges) {
      final _MarkdownSelectionSegment segment = segmentRange.segment;
      final bool isEmptySegment = segmentRange.start == segmentRange.end;
      final bool intersects = isEmptySegment
          ? selectionStart < segmentRange.start &&
              selectionEnd > segmentRange.start
          : selectionStart < segmentRange.end &&
              selectionEnd > segmentRange.start;
      if (!intersects) {
        continue;
      }

      final String markdownText = isEmptySegment
          ? segment.markdownText
          : segment.markdownForPlainRange(
              (selectionStart - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
              (selectionEnd - segmentRange.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(markdownText);
    }

    return out.toString();
  }

  _MarkdownSourceSelectionRange? sourceRangeForSelectedPlainText(
    String selectedPlainText, {
    int? preferredPlainStart,
  }) {
    final _MarkdownSelectionRange? plainRange = findRangeForSelectedPlainText(
      selectedPlainText,
      preferredStart: preferredPlainStart,
    );
    if (plainRange == null) {
      return null;
    }
    return sourceRangeForPlainRange(plainRange, plainSeparator: '\n\n');
  }

  _MarkdownSelectionRange? displayRangeForCompactRange(
    _MarkdownSelectionRange range,
  ) {
    final int compactLength = _compactPlainTextLength;
    if (compactLength <= 0) {
      return null;
    }
    final int rawStart = range.start < range.end ? range.start : range.end;
    final int rawEnd = range.start < range.end ? range.end : range.start;
    final int selectionStart = rawStart.clamp(0, compactLength);
    final int selectionEnd = rawEnd.clamp(selectionStart, compactLength);
    if (selectionStart >= selectionEnd) {
      return null;
    }
    return _MarkdownSelectionRange(
      start: _displayOffsetForCompactOffset(
        selectionStart,
        preferNextAtBoundary: true,
      ),
      end: _displayOffsetForCompactOffset(
        selectionEnd,
        preferNextAtBoundary: false,
      ),
    );
  }

  _MarkdownSourceSelectionRange? sourceRangeForPlainRange(
    _MarkdownSelectionRange range, {
    required String plainSeparator,
  }) {
    final List<_MarkdownSelectionSegmentRange> plainRanges =
        <_MarkdownSelectionSegmentRange>[];
    final List<_MarkdownSelectionSegmentRange> markdownRanges =
        <_MarkdownSelectionSegmentRange>[];

    int plainCursor = 0;
    int markdownCursor = 0;
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plainCursor += plainSeparator.length;
        markdownCursor += 2;
      }
      final _MarkdownSelectionSegment segment = segments[i];
      final int plainStart = plainCursor;
      final int markdownStart = markdownCursor;
      plainCursor += segment.plainText.length;
      markdownCursor += segment.markdownText.length;
      plainRanges.add(
        _MarkdownSelectionSegmentRange(
          segment: segment,
          start: plainStart,
          end: plainCursor,
        ),
      );
      markdownRanges.add(
        _MarkdownSelectionSegmentRange(
          segment: segment,
          start: markdownStart,
          end: markdownCursor,
        ),
      );
    }

    final int selectionStart = range.start.clamp(0, plainCursor);
    final int selectionEnd = range.end.clamp(selectionStart, plainCursor);
    int? sourceStart;
    int? sourceEnd;

    for (int i = 0; i < plainRanges.length; i++) {
      final _MarkdownSelectionSegmentRange plainRange = plainRanges[i];
      final _MarkdownSelectionSegmentRange markdownRange = markdownRanges[i];
      final _MarkdownSelectionSegment segment = plainRange.segment;
      final bool intersects =
          selectionStart < plainRange.end && selectionEnd > plainRange.start;
      if (!intersects) {
        continue;
      }

      final int localStart = (selectionStart - plainRange.start)
          .clamp(0, segment.plainText.length);
      final int localEnd =
          (selectionEnd - plainRange.start).clamp(0, segment.plainText.length);
      final _MarkdownSelectionRange? localMarkdownRange =
          segment.markdownRangeForPlainRange(localStart, localEnd);
      if (localMarkdownRange == null) {
        continue;
      }
      sourceStart ??= markdownRange.start + localMarkdownRange.start;
      sourceEnd = markdownRange.start + localMarkdownRange.end;
    }

    if (sourceStart == null || sourceEnd == null || sourceStart >= sourceEnd) {
      return null;
    }
    return _MarkdownSourceSelectionRange(start: sourceStart, end: sourceEnd);
  }

  TextSelection? sourceSelectionForPlainSelection(
    TextSelection selection, {
    required String plainSeparator,
  }) {
    if (!selection.isValid || selection.isCollapsed) {
      return null;
    }
    final _MarkdownSourceSelectionRange? range = sourceRangeForPlainRange(
      _MarkdownSelectionRange(
        start: selection.start,
        end: selection.end,
      ),
      plainSeparator: plainSeparator,
    );
    if (range == null) {
      return null;
    }
    final bool forward = selection.baseOffset <= selection.extentOffset;
    return TextSelection(
      baseOffset: forward ? range.start : range.end,
      extentOffset: forward ? range.end : range.start,
      affinity: selection.affinity,
      isDirectional: true,
    );
  }

  TextSelection plainSelectionForSourceSelection(
    TextSelection selection, {
    String plainSeparator = '\n\n',
  }) {
    if (!selection.isValid) {
      return const TextSelection.collapsed(offset: -1);
    }
    return TextSelection(
      baseOffset: plainOffsetForSourceOffset(
        selection.baseOffset,
        plainSeparator: plainSeparator,
        preferNextAtBoundary: true,
      ),
      extentOffset: plainOffsetForSourceOffset(
        selection.extentOffset,
        plainSeparator: plainSeparator,
        preferNextAtBoundary: false,
      ),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  int sourceOffsetForPlainOffset(
    int offset, {
    String plainSeparator = '\n\n',
    required bool preferNextAtBoundary,
  }) {
    int plainCursor = 0;
    int sourceCursor = 0;
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        final int separatorStart = plainCursor;
        plainCursor += plainSeparator.length;
        if (offset < plainCursor ||
            (!preferNextAtBoundary && offset == plainCursor)) {
          final int local = (offset - separatorStart).clamp(0, 2);
          return (sourceCursor + local).clamp(0, fullMarkdownText.length);
        }
        sourceCursor += 2;
      }
      final _MarkdownSelectionSegment segment = segments[i];
      final int plainEnd = plainCursor + segment.plainText.length;
      final bool belongsToSegment = offset < plainEnd ||
          (!preferNextAtBoundary && offset == plainEnd) ||
          i == segments.length - 1;
      if (belongsToSegment) {
        final int local = (offset - plainCursor).clamp(
          0,
          segment.plainText.length,
        );
        return sourceCursor +
            segment.markdownOffsetForPlainOffset(
              local,
              preferNextAtBoundary: preferNextAtBoundary,
            );
      }
      plainCursor = plainEnd;
      sourceCursor += segment.markdownText.length;
    }
    return sourceCursor;
  }

  int plainOffsetForSourceOffset(
    int offset, {
    String plainSeparator = '\n\n',
    required bool preferNextAtBoundary,
  }) {
    int sourceCursor = 0;
    int plainCursor = 0;
    final int sourceLength = fullMarkdownText.length;
    final int resolvedOffset = offset.clamp(0, sourceLength);
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        final int separatorStart = sourceCursor;
        sourceCursor += 2;
        if (resolvedOffset < sourceCursor ||
            (!preferNextAtBoundary && resolvedOffset == sourceCursor)) {
          final int local = resolvedOffset - separatorStart;
          return plainCursor + local.clamp(0, plainSeparator.length);
        }
        plainCursor += plainSeparator.length;
      }
      final _MarkdownSelectionSegment segment = segments[i];
      final int sourceEnd = sourceCursor + segment.markdownText.length;
      final bool belongsToSegment = resolvedOffset < sourceEnd ||
          (!preferNextAtBoundary && resolvedOffset == sourceEnd) ||
          i == segments.length - 1;
      if (belongsToSegment) {
        final int local = (resolvedOffset - sourceCursor).clamp(
          0,
          segment.markdownText.length,
        );
        return plainCursor +
            segment.plainOffsetForMarkdownOffset(
              local,
              preferNextAtBoundary: preferNextAtBoundary,
            );
      }
      sourceCursor = sourceEnd;
      plainCursor += segment.plainText.length;
    }
    return plainCursor;
  }

  int _displayOffsetForCompactOffset(
    int offset, {
    required bool preferNextAtBoundary,
  }) {
    int compactCursor = 0;
    int displayCursor = 0;
    for (int i = 0; i < segments.length; i++) {
      final int length = segments[i].plainText.length;
      final int compactEnd = compactCursor + length;
      final bool atBoundary = offset == compactEnd;
      final bool withinSegment = offset < compactEnd ||
          (!preferNextAtBoundary && atBoundary) ||
          i == segments.length - 1;
      if (withinSegment) {
        return displayCursor + (offset - compactCursor).clamp(0, length);
      }
      compactCursor = compactEnd;
      displayCursor += length;
      if (i < segments.length - 1) {
        displayCursor += 2;
      }
    }
    return displayCursor;
  }

  String markdownForSourceRange(_MarkdownSourceSelectionRange range) {
    final String markdown = fullMarkdownText;
    final int start = range.start.clamp(0, markdown.length);
    final int end = range.end.clamp(start, markdown.length);
    if (start >= end) {
      return '';
    }
    return markdown.substring(start, end);
  }

  String plainTextForSelectedPlainText(String selectedPlainText) {
    final String selected = selectedPlainText.replaceAll('\r', '');
    if (selected.isEmpty) {
      return '';
    }

    for (final _MarkdownSelectionSegment segment in segments) {
      if (segment.plainText == selected) {
        return selected;
      }
    }

    final String withDisplaySeparators = _plainTextForDocumentSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (withDisplaySeparators.isNotEmpty) {
      return withDisplaySeparators;
    }

    final String compact = _plainTextForDocumentSelection(
      selected,
      plainSeparator: '',
    );
    if (compact.isNotEmpty) {
      return compact;
    }

    final String whitespaceNormalized =
        _plainTextForWhitespaceNormalizedSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (whitespaceNormalized.isNotEmpty) {
      return whitespaceNormalized;
    }

    final String containedSegments = _plainTextForContainedSegments(selected);
    if (containedSegments.isNotEmpty) {
      return containedSegments;
    }

    return selected;
  }

  String markdownForSelectedPlainText(String selectedPlainText) {
    final String selected = selectedPlainText.replaceAll('\r', '');
    if (selected.isEmpty) {
      if (segments.length == 1 &&
          segments.first.plainText.isEmpty &&
          segments.first.markdownText.isNotEmpty) {
        return segments.first.markdownText;
      }
      return '';
    }

    for (final _MarkdownSelectionSegment segment in segments) {
      final String exact = segment.markdownForPlainText(selected);
      if (exact.isNotEmpty) {
        return exact;
      }
    }

    final String withDisplaySeparators = _markdownForDocumentSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (withDisplaySeparators.isNotEmpty) {
      return withDisplaySeparators;
    }

    final String compact = _markdownForDocumentSelection(
      selected,
      plainSeparator: '',
    );
    if (compact.isNotEmpty) {
      return compact;
    }

    final String whitespaceNormalized =
        _markdownForWhitespaceNormalizedSelection(
      selected,
      plainSeparator: '\n\n',
    );
    if (whitespaceNormalized.isNotEmpty) {
      return whitespaceNormalized;
    }

    final String containedSegments = _markdownForContainedSegments(selected);
    if (containedSegments.isNotEmpty) {
      return containedSegments;
    }

    return selected;
  }

  String _plainTextForWhitespaceNormalizedSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final _NormalizedDocumentSelectionMatch? match =
        _matchWhitespaceNormalizedSelection(
      selectedPlainText,
      plainSeparator: plainSeparator,
    );
    if (match == null) {
      return '';
    }

    final StringBuffer out = StringBuffer();
    for (final _MarkdownSelectionSegmentRange range in match.ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? match.selectionStart < range.start &&
              match.selectionEnd > range.start
          : match.selectionStart < range.end &&
              match.selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String piece = isEmptySegment
          ? ''
          : segment.plainText.substring(
              (match.selectionStart - range.start)
                  .clamp(0, segment.plainText.length),
              (match.selectionEnd - range.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (piece.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(piece);
    }
    return out.toString();
  }

  String _markdownForWhitespaceNormalizedSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final _NormalizedDocumentSelectionMatch? match =
        _matchWhitespaceNormalizedSelection(
      selectedPlainText,
      plainSeparator: plainSeparator,
    );
    if (match == null) {
      return '';
    }

    final StringBuffer out = StringBuffer();
    for (final _MarkdownSelectionSegmentRange range in match.ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? match.selectionStart < range.start &&
              match.selectionEnd > range.start
          : match.selectionStart < range.end &&
              match.selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String markdownText = isEmptySegment
          ? segment.markdownText
          : segment.markdownForPlainRange(
              (match.selectionStart - range.start)
                  .clamp(0, segment.plainText.length),
              (match.selectionEnd - range.start).clamp(
                0,
                segment.plainText.length,
              ),
            );
      if (markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(markdownText);
    }
    return out.toString();
  }

  _NormalizedDocumentSelectionMatch? _matchWhitespaceNormalizedSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write(plainSeparator);
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final _NormalizedSelectionText normalizedDocument =
        _NormalizedSelectionText.from(plain.toString());
    final _NormalizedSelectionText normalizedSelected =
        _NormalizedSelectionText.from(selectedPlainText);
    if (normalizedDocument.value.isEmpty || normalizedSelected.value.isEmpty) {
      return null;
    }

    final int normalizedStart = normalizedDocument.value.indexOf(
      normalizedSelected.value,
    );
    if (normalizedStart < 0) {
      return null;
    }
    final int normalizedEnd = normalizedStart + normalizedSelected.value.length;
    final int selectionStart =
        normalizedDocument.originalIndexAt(normalizedStart);
    final int selectionEnd =
        normalizedDocument.originalEndIndexAt(normalizedEnd - 1);
    return _NormalizedDocumentSelectionMatch(
      ranges: ranges,
      selectionStart: selectionStart,
      selectionEnd: selectionEnd,
    );
  }

  String _plainTextForContainedSegments(String selectedPlainText) {
    final List<int> selectedIndexes = <int>[];
    for (int i = 0; i < segments.length; i++) {
      final String plainText = segments[i].plainText;
      if (plainText.isNotEmpty && selectedPlainText.contains(plainText)) {
        selectedIndexes.add(i);
      }
    }
    if (selectedIndexes.length <= 1) {
      return '';
    }

    final int first = selectedIndexes.first;
    final int last = selectedIndexes.last;
    final StringBuffer out = StringBuffer();
    for (int i = first; i <= last; i++) {
      final _MarkdownSelectionSegment segment = segments[i];
      if (segment.plainText.isEmpty && segment.markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(segment.plainText);
    }
    return out.toString();
  }

  String _markdownForContainedSegments(String selectedPlainText) {
    final List<int> selectedIndexes = <int>[];
    for (int i = 0; i < segments.length; i++) {
      final String plainText = segments[i].plainText;
      if (plainText.isNotEmpty && selectedPlainText.contains(plainText)) {
        selectedIndexes.add(i);
      }
    }
    if (selectedIndexes.length <= 1) {
      return '';
    }

    final int first = selectedIndexes.first;
    final int last = selectedIndexes.last;
    final StringBuffer out = StringBuffer();
    for (int i = first; i <= last; i++) {
      final _MarkdownSelectionSegment segment = segments[i];
      if (segment.plainText.isEmpty && segment.markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(segment.markdownText);
    }
    return out.toString();
  }

  String _plainTextForDocumentSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write(plainSeparator);
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final String plainText = plain.toString();
    final int selectionStart = plainText.indexOf(selectedPlainText);
    if (selectionStart < 0) {
      return '';
    }
    final int selectionEnd = selectionStart + selectedPlainText.length;
    final StringBuffer out = StringBuffer();

    for (final _MarkdownSelectionSegmentRange range in ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? selectionStart < range.start && selectionEnd > range.start
          : selectionStart < range.end && selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String piece = isEmptySegment
          ? ''
          : segment.plainText.substring(
              (selectionStart - range.start).clamp(0, segment.plainText.length),
              (selectionEnd - range.start).clamp(0, segment.plainText.length),
            );
      if (piece.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(piece);
    }

    return out.toString();
  }

  String _markdownForDocumentSelection(
    String selectedPlainText, {
    required String plainSeparator,
  }) {
    final StringBuffer plain = StringBuffer();
    final List<_MarkdownSelectionSegmentRange> ranges =
        <_MarkdownSelectionSegmentRange>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        plain.write(plainSeparator);
      }
      final int start = plain.length;
      plain.write(segments[i].plainText);
      ranges.add(
        _MarkdownSelectionSegmentRange(
          segment: segments[i],
          start: start,
          end: plain.length,
        ),
      );
    }

    final String plainText = plain.toString();
    final int selectionStart = plainText.indexOf(selectedPlainText);
    if (selectionStart < 0) {
      return '';
    }
    final int selectionEnd = selectionStart + selectedPlainText.length;
    final StringBuffer out = StringBuffer();

    for (final _MarkdownSelectionSegmentRange range in ranges) {
      final _MarkdownSelectionSegment segment = range.segment;
      final bool isEmptySegment = range.start == range.end;
      final bool intersects = isEmptySegment
          ? selectionStart < range.start && selectionEnd > range.start
          : selectionStart < range.end && selectionEnd > range.start;
      if (!intersects) {
        continue;
      }

      final String markdownText = isEmptySegment
          ? segment.markdownText
          : segment.markdownForPlainRange(
              (selectionStart - range.start).clamp(0, segment.plainText.length),
              (selectionEnd - range.start).clamp(0, segment.plainText.length),
            );
      if (markdownText.isEmpty) {
        continue;
      }
      if (out.isNotEmpty) {
        out.write('\n\n');
      }
      out.write(markdownText);
    }

    return out.toString();
  }
}

class _MarkdownSelectionRange {
  const _MarkdownSelectionRange({required this.start, required this.end});

  final int start;
  final int end;

  @override
  bool operator ==(Object other) {
    return other is _MarkdownSelectionRange &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

class _MarkdownSourceSelectionRange {
  const _MarkdownSourceSelectionRange({required this.start, required this.end});

  final int start;
  final int end;

  @override
  bool operator ==(Object other) {
    return other is _MarkdownSourceSelectionRange &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);
}

class _MarkdownSelectionBlockRange {
  const _MarkdownSelectionBlockRange({
    required this.sourceRange,
    required this.plainRange,
    required this.compactRange,
  });

  final _MarkdownSourceSelectionRange sourceRange;
  final _MarkdownSelectionRange plainRange;
  final _MarkdownSelectionRange compactRange;
}

class _NormalizedDocumentSelectionMatch {
  const _NormalizedDocumentSelectionMatch({
    required this.ranges,
    required this.selectionStart,
    required this.selectionEnd,
  });

  final List<_MarkdownSelectionSegmentRange> ranges;
  final int selectionStart;
  final int selectionEnd;
}

class _NormalizedSelectionText {
  _NormalizedSelectionText._(this.value, this._indexMap);

  final String value;
  final List<int> _indexMap;

  factory _NormalizedSelectionText.from(String source) {
    final StringBuffer normalized = StringBuffer();
    final List<int> indexMap = <int>[];
    for (int i = 0; i < source.length; i++) {
      final String char = source[i];
      if (_isWhitespace(char)) {
        continue;
      }
      normalized.write(char);
      indexMap.add(i);
    }
    return _NormalizedSelectionText._(normalized.toString(), indexMap);
  }

  int originalIndexAt(int normalizedIndex) {
    return _indexMap[normalizedIndex];
  }

  int originalEndIndexAt(int normalizedIndex) {
    return _indexMap[normalizedIndex] + 1;
  }

  static bool _isWhitespace(String char) {
    switch (char) {
      case ' ':
      case '\n':
      case '\r':
      case '\t':
      case '\f':
      case '\v':
        return true;
      default:
        return false;
    }
  }
}
