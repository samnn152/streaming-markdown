part of '../view.dart';

extension _StreamingMarkdownInlineParsing on StreamingMarkdownRenderView {
  List<_InlineToken> _parseInlineTokens(
    String text, {
    _InlineStyle style = const _InlineStyle(),
    Map<String, String> references = const <String, String>{},
    int depth = 0,
    bool allowUnclosedDelimiters = false,
  }) {
    if (text.isEmpty) {
      return <_InlineToken>[];
    }
    if (depth > 8) {
      return <_InlineToken>[
        _InlineToken.text(text: text, style: style, sourceMarkdown: text),
      ];
    }

    final List<_InlineToken> tokens = <_InlineToken>[];
    final StringBuffer plain = StringBuffer();

    void flushPlain() {
      if (plain.isEmpty) {
        return;
      }
      final String value = plain.toString();
      tokens.add(
          _InlineToken.text(text: value, style: style, sourceMarkdown: value));
      plain.clear();
    }

    int i = 0;
    while (i < text.length) {
      if (text.startsWith('![', i)) {
        final _InlineImageMatch? image = _matchInlineImageAt(text, i);
        if (image != null) {
          flushPlain();
          tokens.add(
            _InlineToken.image(
              altText: image.alt,
              imageUrl: image.url,
              sourceMarkdown: text.substring(i, image.end),
            ),
          );
          i = image.end;
          continue;
        }
      }

      if (text.codeUnitAt(i) == 91) {
        final _FootnoteReferenceMatch? footnoteRef = _matchFootnoteReferenceAt(
          text,
          i,
        );
        if (footnoteRef != null) {
          flushPlain();
          tokens.add(
            _InlineToken.footnote(
              footnoteReferenceId: footnoteRef.id,
              sourceMarkdown: text.substring(i, footnoteRef.end),
            ),
          );
          i = footnoteRef.end;
          continue;
        }

        final _InlineLinkMatch? link = _matchInlineLinkAt(
          text,
          i,
          references: references,
        );
        if (link != null) {
          flushPlain();
          final List<_InlineToken> labelTokens = _parseInlineTokens(
            link.label,
            style: style,
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          );
          if (labelTokens.isEmpty) {
            tokens.add(
              _InlineToken.text(
                text: link.label,
                style: style,
                linkUrl: link.url,
                sourceMarkdown: text.substring(i, link.end),
              ),
            );
          } else {
            for (final _InlineToken token in labelTokens) {
              if (token.isImage) {
                tokens.add(token);
              } else {
                tokens.add(
                  token.withLink(link.url,
                      sourceMarkdown: text.substring(i, link.end)),
                );
              }
            }
          }
          i = link.end;
          continue;
        }
      }

      if (text.startsWith('<http://', i) || text.startsWith('<https://', i)) {
        final int end = text.indexOf('>', i + 1);
        if (end != -1) {
          flushPlain();
          final String url = text.substring(i + 1, end);
          tokens.add(
            _InlineToken.text(
              text: url,
              style: style,
              linkUrl: url,
              sourceMarkdown: text.substring(i, end + 1),
            ),
          );
          i = end + 1;
          continue;
        }
      }

      final _DelimitedMatch? code = _matchDelimited(text, i, '`');
      if (code != null) {
        flushPlain();
        tokens.add(
          _InlineToken.text(
            text: code.inner,
            style: style.copyWith(code: true),
            sourceMarkdown: text.substring(i, code.end),
          ),
        );
        i = code.end;
        continue;
      }

      final _DelimitedMatch? boldItalicStar = _matchDelimited(
        text,
        i,
        '***',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (boldItalicStar != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            boldItalicStar.inner,
            style: style.copyWith(bold: true, italic: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = boldItalicStar.end;
        continue;
      }

      final _DelimitedMatch? boldItalicUnderscore = _matchDelimited(
        text,
        i,
        '___',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (boldItalicUnderscore != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            boldItalicUnderscore.inner,
            style: style.copyWith(bold: true, italic: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = boldItalicUnderscore.end;
        continue;
      }

      final _DelimitedMatch? bold = _matchAnyDelimited(
          text,
          i,
          const <String>[
            '**',
            '__',
          ],
          allowUnclosedDelimiters: allowUnclosedDelimiters);
      if (bold != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            bold.inner,
            style: style.copyWith(bold: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = bold.end;
        continue;
      }

      final _DelimitedMatch? strike = _matchDelimited(text, i, '~~');
      if (strike != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            strike.inner,
            style: style.copyWith(strikethrough: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = strike.end;
        continue;
      }

      final _DelimitedMatch? italicStar = _matchDelimited(
        text,
        i,
        '*',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (italicStar != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            italicStar.inner,
            style: style.copyWith(italic: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = italicStar.end;
        continue;
      }

      final _DelimitedMatch? italicUnderscore = _matchDelimited(
        text,
        i,
        '_',
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (italicUnderscore != null) {
        flushPlain();
        tokens.addAll(
          _parseInlineTokens(
            italicUnderscore.inner,
            style: style.copyWith(italic: true),
            references: references,
            depth: depth + 1,
            allowUnclosedDelimiters: allowUnclosedDelimiters,
          ),
        );
        i = italicUnderscore.end;
        continue;
      }

      plain.write(text[i]);
      i += 1;
    }

    flushPlain();
    return tokens;
  }

  _DelimitedMatch? _matchAnyDelimited(
    String text,
    int start,
    List<String> delimiters, {
    required bool allowUnclosedDelimiters,
  }) {
    for (final String delimiter in delimiters) {
      final _DelimitedMatch? match = _matchDelimited(
        text,
        start,
        delimiter,
        allowUnclosedTail: allowUnclosedDelimiters,
      );
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  _FootnoteReferenceMatch? _matchFootnoteReferenceAt(String text, int start) {
    final Match? match = RegExp(r'\[\^([^\]]+)\]').matchAsPrefix(text, start);
    if (match is! RegExpMatch) {
      return null;
    }
    return _FootnoteReferenceMatch(id: match.group(1)!, end: match.end);
  }
}
