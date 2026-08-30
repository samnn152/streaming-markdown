/// Semantic state of an inline Markdown link while its source is streaming.
///
/// Offsets are UTF-16 offsets relative to the source string that was scanned.
class MarkdownInlineLink {
  /// Creates an immutable inline-link snapshot.
  const MarkdownInlineLink({
    required this.label,
    required this.destination,
    required this.isCompleted,
    required this.source,
    required this.start,
    required this.end,
  });

  /// Link label without the surrounding square brackets.
  final String label;

  /// Destination received so far, without surrounding angle brackets or title.
  final String destination;

  /// Whether the closing `)` has arrived.
  final bool isCompleted;

  /// Original, lossless Markdown source for this link state.
  final String source;

  /// Inclusive offset in the scanned source.
  final int start;

  /// Exclusive offset in the scanned source.
  final int end;

  /// Whether at least one destination character has arrived.
  bool get hasDestination => destination.isNotEmpty;

  @override
  bool operator ==(Object other) {
    return other is MarkdownInlineLink &&
        other.label == label &&
        other.destination == destination &&
        other.isCompleted == isCompleted &&
        other.source == source &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(
        label,
        destination,
        isCompleted,
        source,
        start,
        end,
      );
}

/// Finds direct inline links in [source], including one provisional link at the
/// active tail.
///
/// Code spans, autolinks, images, and escaped opening brackets are deliberately
/// excluded. An unfinished construct is only recognized when it reaches the
/// end of [source], which matches the append-only streaming constraint.
List<MarkdownInlineLink> parseMarkdownInlineLinks(String source) {
  if (source.isEmpty) {
    return const <MarkdownInlineLink>[];
  }

  final List<MarkdownInlineLink> links = <MarkdownInlineLink>[];
  int index = 0;
  while (index < source.length) {
    final int codeUnit = source.codeUnitAt(index);
    if (codeUnit == 0x5c) {
      index += index + 1 < source.length ? 2 : 1;
      continue;
    }
    if (codeUnit == 0x60) {
      index = _skipCodeSpan(source, index);
      continue;
    }
    if (codeUnit == 0x3c) {
      final int closeAngle = source.indexOf('>', index + 1);
      if (closeAngle == -1 &&
          (source.startsWith('<http://', index) ||
              source.startsWith('<https://', index))) {
        break;
      }
      if (closeAngle != -1) {
        index = closeAngle + 1;
        continue;
      }
    }
    if (codeUnit == 0x5b &&
        (index == 0 || source.codeUnitAt(index - 1) != 0x21)) {
      final MarkdownInlineLink? link = matchMarkdownInlineLink(source, index);
      if (link != null) {
        links.add(link);
        index = link.end;
        continue;
      }
    }
    index += 1;
  }
  return List<MarkdownInlineLink>.unmodifiable(links);
}

/// Matches a direct inline link beginning at [start].
///
/// This is exposed for custom inline renderers that already own their scanning
/// loop. Most consumers should use [parseMarkdownInlineLinks] or
/// `MarkdownBlock.inlineLinks`.
MarkdownInlineLink? matchMarkdownInlineLink(String source, int start) {
  if (start < 0 ||
      start >= source.length ||
      source.codeUnitAt(start) != 0x5b ||
      _isEscapedAt(source, start) ||
      (start > 0 && source.codeUnitAt(start - 1) == 0x21)) {
    return null;
  }

  final int closeBracket = _findClosingLabelBracket(source, start + 1);
  if (closeBracket == -1) {
    final String label = source.substring(start + 1);
    if (label.isEmpty || label.contains('\n')) {
      return null;
    }
    return MarkdownInlineLink(
      label: label,
      destination: '',
      isCompleted: false,
      source: source.substring(start),
      start: start,
      end: source.length,
    );
  }

  final String label = source.substring(start + 1, closeBracket);
  if (label.isEmpty ||
      closeBracket + 1 >= source.length ||
      source.codeUnitAt(closeBracket + 1) != 0x28) {
    return null;
  }

  final int destinationStart = closeBracket + 2;
  int nestedParentheses = 0;
  for (int index = destinationStart; index < source.length; index++) {
    if (_isEscapedAt(source, index)) {
      continue;
    }
    final int codeUnit = source.codeUnitAt(index);
    if (codeUnit == 0x28) {
      nestedParentheses += 1;
      continue;
    }
    if (codeUnit != 0x29) {
      continue;
    }
    if (nestedParentheses > 0) {
      nestedParentheses -= 1;
      continue;
    }

    final String destination = _destinationFromRaw(
      source.substring(destinationStart, index),
    );
    if (destination.isEmpty) {
      return null;
    }
    return MarkdownInlineLink(
      label: label,
      destination: destination,
      isCompleted: true,
      source: source.substring(start, index + 1),
      start: start,
      end: index + 1,
    );
  }

  return MarkdownInlineLink(
    label: label,
    destination: _destinationFromRaw(source.substring(destinationStart)),
    isCompleted: false,
    source: source.substring(start),
    start: start,
    end: source.length,
  );
}

int _findClosingLabelBracket(String source, int start) {
  int nestedBrackets = 0;
  for (int index = start; index < source.length; index++) {
    if (_isEscapedAt(source, index)) {
      continue;
    }
    final int codeUnit = source.codeUnitAt(index);
    if (codeUnit == 0x5b) {
      nestedBrackets += 1;
    } else if (codeUnit == 0x5d) {
      if (nestedBrackets == 0) {
        return index;
      }
      nestedBrackets -= 1;
    }
  }
  return -1;
}

String _destinationFromRaw(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.codeUnitAt(0) == 0x3c) {
    final int closeAngle = trimmed.indexOf('>', 1);
    return closeAngle == -1
        ? trimmed.substring(1)
        : trimmed.substring(1, closeAngle);
  }

  for (int index = 0; index < trimmed.length; index++) {
    if (!_isEscapedAt(trimmed, index)) {
      final int codeUnit = trimmed.codeUnitAt(index);
      if (codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0a) {
        return trimmed.substring(0, index);
      }
    }
  }
  return trimmed;
}

int _skipCodeSpan(String source, int start) {
  int markerLength = 1;
  while (start + markerLength < source.length &&
      source.codeUnitAt(start + markerLength) == 0x60) {
    markerLength += 1;
  }
  final String marker = source.substring(start, start + markerLength);
  final int close = source.indexOf(marker, start + markerLength);
  return close == -1 ? source.length : close + markerLength;
}

bool _isEscapedAt(String source, int index) {
  int slashCount = 0;
  for (int cursor = index - 1;
      cursor >= 0 && source.codeUnitAt(cursor) == 0x5c;
      cursor--) {
    slashCount += 1;
  }
  return slashCount.isOdd;
}
