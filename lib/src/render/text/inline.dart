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
          if (!link.isCompleted) {
            final MarkdownInlineLink semanticLink = MarkdownInlineLink(
              label: link.label,
              destination: link.url,
              isCompleted: false,
              source: link.sourceMarkdown,
              start: i,
              end: link.end,
            );
            final String projection = incompleteLinkTextBuilder?.call(
                  semanticLink,
                ) ??
                semanticLink.destination;
            tokens.add(
              _InlineToken.text(
                text: projection,
                style: style,
                linkUrl: semanticLink.hasDestination
                    ? semanticLink.destination
                    : null,
                sourceMarkdown: link.sourceMarkdown,
              ),
            );
            i = link.end;
            continue;
          }
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
                sourceMarkdown: link.sourceMarkdown,
              ),
            );
          } else {
            for (final _InlineToken token in labelTokens) {
              if (token.isImage) {
                tokens.add(token);
              } else {
                tokens.add(
                  token.withLink(
                    link.url,
                    sourceMarkdown: link.sourceMarkdown,
                  ),
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

      final _LatexMatch? latex = _matchLatexAt(text, i);
      if (latex != null) {
        flushPlain();
        tokens.add(
          _InlineToken.latex(
            latexExpression: latex.expression,
            latexDisplay: latex.display,
            sourceMarkdown: latex.sourceMarkdown,
          ),
        );
        i = latex.end;
        continue;
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

  _LatexMatch? _matchLatexAt(String text, int start) {
    if (start > 0 && text.codeUnitAt(start - 1) == 92) {
      return null;
    }

    if (text.startsWith(r'\(', start)) {
      return _matchDelimitedLatex(
        text,
        start,
        open: r'\(',
        close: r'\)',
        display: false,
      );
    }
    if (text.startsWith(r'\[', start)) {
      return _matchDelimitedLatex(
        text,
        start,
        open: r'\[',
        close: r'\]',
        display: true,
      );
    }
    if (text.startsWith(r'$$', start)) {
      return _matchDelimitedLatex(
        text,
        start,
        open: r'$$',
        close: r'$$',
        display: true,
      );
    }
    if (text.codeUnitAt(start) == 36) {
      if (start + 1 >= text.length || text.codeUnitAt(start + 1) == 36) {
        return null;
      }
      final _LatexMatch? match = _matchDelimitedLatex(
        text,
        start,
        open: r'$',
        close: r'$',
        display: false,
      );
      if (match == null) {
        return null;
      }
      return match;
    }
    return null;
  }

  _LatexMatch? _matchDelimitedLatex(
    String text,
    int start, {
    required String open,
    required String close,
    required bool display,
  }) {
    if (!text.startsWith(open, start)) {
      return null;
    }
    final int contentStart = start + open.length;
    final int closeStart = _findUnescapedDelimiter(text, close, contentStart);
    if (closeStart == -1 || closeStart == contentStart) {
      return null;
    }
    final int end = closeStart + close.length;
    final String expression = text.substring(contentStart, closeStart).trim();
    if (expression.isEmpty) {
      return null;
    }
    return _LatexMatch(
      expression: expression,
      sourceMarkdown: text.substring(start, end),
      display: display,
      end: end,
    );
  }

  int _findUnescapedDelimiter(String text, String delimiter, int start) {
    int index = start;
    while (index < text.length) {
      final int found = text.indexOf(delimiter, index);
      if (found == -1) {
        return -1;
      }
      if (!_isEscaped(text, found)) {
        return found;
      }
      index = found + delimiter.length;
    }
    return -1;
  }

  bool _isEscaped(String text, int index) {
    int slashCount = 0;
    int cursor = index - 1;
    while (cursor >= 0 && text.codeUnitAt(cursor) == 92) {
      slashCount += 1;
      cursor -= 1;
    }
    return slashCount.isOdd;
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
