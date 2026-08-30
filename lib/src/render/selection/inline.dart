part of '../view.dart';

extension _StreamingMarkdownSelectionInlineBuilder
    on StreamingMarkdownRenderView {
  _MarkdownSelectionSegment _inlineSelectionSegment(
    String text, {
    required String markdownText,
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final List<_InlineToken> tokens = _parseInlineTokens(
      text.replaceAll('\r', ''),
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<_MarkdownSelectionPiece> pieces = <_MarkdownSelectionPiece>[];
    for (final _InlineToken token in tokens) {
      if (token.isImage) {
        pieces.add(
          _MarkdownSelectionPiece(
            plainText:
                token.altText.isEmpty ? '[image]' : '[image: ${token.altText}]',
            markdownText: token.sourceMarkdown,
          ),
        );
        continue;
      }
      if (token.isFootnoteReference) {
        final int? number = _footnoteNumberForId(
          footnoteNumbers,
          token.footnoteReferenceId!,
        );
        pieces.add(
          _MarkdownSelectionPiece(
            plainText: number?.toString() ?? token.footnoteReferenceId!,
            markdownText: token.sourceMarkdown,
          ),
        );
        continue;
      }
      if (token.isLatex) {
        pieces.add(
          _MarkdownSelectionPiece(
            plainText: token.sourceMarkdown,
            markdownText: token.sourceMarkdown,
          ),
        );
        continue;
      }
      pieces.add(
        _MarkdownSelectionPiece(
          plainText: token.text,
          markdownText: _semanticMarkdownForInlineToken(token),
        ),
      );
    }
    return _MarkdownSelectionSegment(
      pieces: pieces,
      fallbackMarkdownText: markdownText,
    );
  }

  /// Builds an inline semantic segment when the rendered markdown is embedded
  /// inside block syntax (heading markers, setext delimiters, and similar
  /// wrappers). Keeping the source prefix/suffix in the first and last pieces
  /// makes visual and source offsets describe the same complete block.
  _MarkdownSelectionSegment _embeddedInlineSelectionSegment(
    String visualMarkdown, {
    required String sourceMarkdown,
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
    bool preserveBlockMarkdownOnPartial = false,
  }) {
    final _MarkdownSelectionSegment inline = _inlineSelectionSegment(
      visualMarkdown,
      markdownText: visualMarkdown,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    final int embeddedStart = sourceMarkdown.indexOf(visualMarkdown);
    final String reconstructedInline = inline.pieces
        .map((_MarkdownSelectionPiece piece) => piece.markdownText)
        .join();
    if (embeddedStart < 0 || reconstructedInline != visualMarkdown) {
      return _MarkdownSelectionSegment.plain(
        plainText: inline.plainText,
        markdownText: sourceMarkdown,
        preserveBlockMarkdownOnPartial: preserveBlockMarkdownOnPartial,
      );
    }
    if (inline.pieces.isEmpty) {
      return _MarkdownSelectionSegment.plain(
        plainText: '',
        markdownText: sourceMarkdown,
        preserveBlockMarkdownOnPartial: preserveBlockMarkdownOnPartial,
      );
    }

    final List<_MarkdownSelectionPiece> pieces = inline.pieces
        .map(
          (_MarkdownSelectionPiece piece) => _MarkdownSelectionPiece(
            plainText: piece.plainText,
            markdownText: piece.markdownText,
          ),
        )
        .toList(growable: false);
    final _MarkdownSelectionPiece first = pieces.first;
    pieces[0] = _MarkdownSelectionPiece(
      plainText: first.plainText,
      markdownText:
          '${sourceMarkdown.substring(0, embeddedStart)}${first.markdownText}',
    );
    final int embeddedEnd = embeddedStart + visualMarkdown.length;
    final _MarkdownSelectionPiece last = pieces.last;
    pieces[pieces.length - 1] = _MarkdownSelectionPiece(
      plainText: last.plainText,
      markdownText:
          '${last.markdownText}${sourceMarkdown.substring(embeddedEnd)}',
    );
    return _MarkdownSelectionSegment(
      pieces: pieces,
      fallbackMarkdownText: sourceMarkdown,
      preserveBlockMarkdownOnPartial: preserveBlockMarkdownOnPartial,
    );
  }

  int _inlineSelectionPlainTextLength(
    String text, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    return _inlineSelectionPlainText(
      text,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    ).length;
  }

  String _inlineSelectionPlainText(
    String text, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    return _inlineSelectionSegment(
      text,
      markdownText: text,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    ).plainText;
  }

  String _semanticMarkdownForInlineToken(_InlineToken token) {
    if (token.sourceMarkdown != token.text) {
      return token.sourceMarkdown;
    }

    String markdown = token.text;
    if (token.style.code) {
      markdown = '`$markdown`';
    }
    if (token.style.strikethrough) {
      markdown = '~~$markdown~~';
    }
    if (token.style.bold && token.style.italic) {
      return '***$markdown***';
    }
    if (token.style.bold) {
      markdown = '**$markdown**';
    }
    if (token.style.italic) {
      markdown = '_${markdown}_';
    }
    return markdown;
  }

  String _linkReferencesDigest(Map<String, String> linkReferences) {
    if (linkReferences.isEmpty) {
      return '0';
    }
    final List<MapEntry<String, String>> entries =
        linkReferences.entries.toList(growable: false)
          ..sort(
            (MapEntry<String, String> a, MapEntry<String, String> b) =>
                a.key.compareTo(b.key),
          );
    final StringBuffer buffer = StringBuffer();
    for (final MapEntry<String, String> entry in entries) {
      buffer
        ..write(entry.key)
        ..write('=')
        ..write(entry.value)
        ..write(';');
    }
    return buffer.toString().hashCode.toString();
  }
}
