part of '../view.dart';

class _MarkdownSelectionProjection {
  const _MarkdownSelectionProjection(this.segments);

  final List<_MarkdownSelectionSegment> segments;

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

    final String containedSegments = _markdownForContainedSegments(selected);
    if (containedSegments.isNotEmpty) {
      return containedSegments;
    }

    return selected;
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
