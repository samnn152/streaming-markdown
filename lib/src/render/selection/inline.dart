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
