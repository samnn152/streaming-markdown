part of '../view.dart';

extension _StreamingMarkdownInlineTokenSpans on StreamingMarkdownRenderView {
  static const List<Color> _tokenDebugColors = <Color>[
    Color(0xFFFFF3BF),
    Color(0xFFD3F9D8),
    Color(0xFFFFDEEB),
    Color(0xFFD0EBFF),
    Color(0xFFE5DBFF),
    Color(0xFFFFE8CC),
  ];

  int _appendTokenizedTextSpans({
    required List<InlineSpan> spans,
    required String text,
    required TextStyle style,
    required int startTokenIndex,
    required Duration fadeDuration,
    required Curve fadeCurve,
    required Duration tokenStaggerDelay,
    required DateTime? tokenScheduleOrigin,
    required StreamingMarkdownTokenAnimationBuilder? tokenAnimationBuilder,
    required bool animatePerWord,
    VoidCallback? onTap,
  }) {
    if (!animatePerWord && onTap == null) {
      spans.add(TextSpan(text: text, style: style));
      return startTokenIndex + _inlineWordCount(text);
    }
    if (!animatePerWord) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(onTap: onTap, child: Text(text, style: style)),
        ),
      );
      return startTokenIndex + _inlineWordCount(text);
    }

    int tokenIndex = startTokenIndex;
    for (final RegExpMatch match in RegExp(r'\S+|\s+').allMatches(text)) {
      final String piece = match.group(0) ?? '';
      if (piece.isEmpty) {
        continue;
      }

      if (piece.trim().isEmpty) {
        // Newlines must stay as raw text spans so blocks like quote/code/footnote
        // preserve line breaks exactly as source.
        spans.add(TextSpan(text: piece, style: style));
        continue;
      }

      final Widget tokenWidget;
      if (debugTokenHighlight) {
        final Color bgColor =
            _tokenDebugColors[tokenIndex % _tokenDebugColors.length];
        tokenWidget = Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            piece,
            style: style.copyWith(
              color: style.color ?? const Color(0xFF0D1117),
            ),
          ),
        );
      } else {
        tokenWidget = Text(piece, style: style);
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _FadeInTokenHost(
            key: ValueKey<String>('token_${tokenIndex}_${piece.hashCode}'),
            // Use absolute token index in block so delays do not reset
            // across inline style segments (links/bold/italic/code...).
            initialDelay: tokenScheduleOrigin == null
                ? tokenStaggerDelay * tokenIndex
                : Duration.zero,
            scheduledStart: tokenScheduleOrigin?.add(
              tokenStaggerDelay * tokenIndex,
            ),
            duration: fadeDuration,
            curve: fadeCurve,
            animationBuilder: tokenAnimationBuilder,
            onFadeInEnd: onTokenFadeInEnd,
            child: onTap == null
                ? tokenWidget
                : (debugTokenHighlight
                    ? InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(4),
                        child: tokenWidget,
                      )
                    : GestureDetector(onTap: onTap, child: tokenWidget)),
          ),
        ),
      );
      tokenIndex += 1;
    }
    return tokenIndex;
  }

  int _appendAnimatedWidgetSpan({
    required List<InlineSpan> spans,
    required Widget child,
    required int tokenIndex,
    required Duration fadeDuration,
    required Curve fadeCurve,
    required Duration tokenStaggerDelay,
    required DateTime? tokenScheduleOrigin,
    required StreamingMarkdownTokenAnimationBuilder? tokenAnimationBuilder,
    required PlaceholderAlignment alignment,
    TextBaseline? baseline,
    int tokenUnits = 1,
    bool animate = true,
  }) {
    if (!animate) {
      spans.add(
        WidgetSpan(
          alignment: alignment,
          baseline: baseline,
          child: child,
        ),
      );
      return tokenIndex + (tokenUnits <= 0 ? 1 : tokenUnits);
    }
    spans.add(
      WidgetSpan(
        alignment: alignment,
        baseline: baseline,
        child: _FadeInTokenHost(
          key: ValueKey<String>('widget_token_${tokenIndex}_${child.hashCode}'),
          initialDelay: tokenScheduleOrigin == null
              ? tokenStaggerDelay * tokenIndex
              : Duration.zero,
          scheduledStart: tokenScheduleOrigin?.add(
            tokenStaggerDelay * tokenIndex,
          ),
          duration: fadeDuration,
          curve: fadeCurve,
          animationBuilder: tokenAnimationBuilder,
          onFadeInEnd: onTokenFadeInEnd,
          child: child,
        ),
      ),
    );
    return tokenIndex + (tokenUnits <= 0 ? 1 : tokenUnits);
  }

  int _inlineWordCount(String text) {
    final int count = RegExp(r'\S+').allMatches(text).length;
    return count <= 0 ? 1 : count;
  }

  int _countAnimatedTokenUnits(
    String text, {
    required Map<String, String> linkReferences,
  }) {
    if (text.trim().isEmpty) {
      return 0;
    }
    final List<_InlineToken> tokens = _parseInlineTokens(
      text.replaceAll('\r', ''),
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    if (tokens.isEmpty) {
      return _inlineWordCount(text);
    }
    int total = 0;
    for (final _InlineToken token in tokens) {
      if (token.isImage || token.isFootnoteReference) {
        total += 1;
        continue;
      }
      total += _inlineWordCount(token.text);
    }
    return total;
  }
}
