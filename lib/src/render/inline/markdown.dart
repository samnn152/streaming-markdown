part of '../view.dart';

extension _StreamingMarkdownInlineMarkdownRenderer
    on StreamingMarkdownRenderView {
  Widget _buildInlineMarkdown(
    BuildContext context,
    String text, {
    int tokenStartIndex = 0,
    TextStyle? baseStyle,
    Map<String, String> linkReferences = const <String, String>{},
    Map<String, int> footnoteNumbers = const <String, int>{},
  }) {
    final String normalized = text.replaceAll('\r', '');
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final TextStyle resolvedStyle = baseStyle ??
        markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final bool showSelectionOverlay = enableTextSelection;
    final bool compacted = _TokenCompactionScope.isCompacted(context);
    final bool animatePerWord = !compacted;
    final List<_InlineToken> tokens = _parseInlineTokens(
      normalized,
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    if (tokens.isEmpty) {
      return Text(normalized, style: resolvedStyle);
    }
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final Duration tokenStaggerDelay = tokenArrivalDelay;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenStaggerDelay;

    final List<InlineSpan> spans = <InlineSpan>[];
    int visualTokenIndex = tokenStartIndex;
    for (final _InlineToken token in tokens) {
      if (token.isImage) {
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Text(
              token.altText.isEmpty ? 'image' : 'image: ${token.altText}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFF0F6FC)),
            ),
          ),
        );
        continue;
      }

      if (token.style.code) {
        final TextStyle inlineCodeStyle = markdownTheme.inlineCodeTextStyle ??
            const TextStyle(
              color: Color(0xFFE6EDF3),
              fontFamily: 'monospace',
              fontSize: 12,
            );
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.middle,
          tokenUnits: _inlineWordCount(token.text),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: markdownTheme.inlineCodeBackgroundColor ??
                  const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(token.text, style: inlineCodeStyle),
          ),
        );
        continue;
      }

      if (token.isFootnoteReference) {
        final int? footnoteNumber = _footnoteNumberForId(
          footnoteNumbers,
          token.footnoteReferenceId!,
        );
        final String label =
            footnoteNumber?.toString() ?? token.footnoteReferenceId!;
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.aboveBaseline,
          baseline: TextBaseline.alphabetic,
          child: Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        continue;
      }

      TextStyle style = resolvedStyle;
      if (token.style.bold) {
        style = style.copyWith(fontWeight: FontWeight.w700);
      }
      if (token.style.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
      if (token.style.strikethrough) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (token.linkUrl != null && token.linkUrl!.isNotEmpty) {
        style = style.merge(
          markdownTheme.linkTextStyle ??
              const TextStyle(
                color: Color(0xFF58A6FF),
                decoration: TextDecoration.underline,
              ),
        );
        visualTokenIndex = _appendTokenizedTextSpans(
          spans: spans,
          text: token.text,
          style: style,
          startTokenIndex: visualTokenIndex,
          fadeDuration: tokenFadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: resolvedTokenStep,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animatePerWord: animatePerWord,
          onTap: showSelectionOverlay
              ? null
              : () => _onLinkPressed(context, token.linkUrl!),
        );
        continue;
      }
      visualTokenIndex = _appendTokenizedTextSpans(
        spans: spans,
        text: token.text,
        style: style,
        startTokenIndex: visualTokenIndex,
        fadeDuration: tokenFadeDuration,
        fadeCurve: tokenFadeInCurve,
        tokenStaggerDelay: resolvedTokenStep,
        tokenScheduleOrigin: tokenScheduleOrigin,
        tokenAnimationBuilder: tokenAnimationBuilder,
        animatePerWord: animatePerWord,
      );
    }

    final Widget animatedRichText = RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(style: resolvedStyle, children: spans),
    );
    final Widget visibleAnimatedLayer = animatedRichText;
    if (!showSelectionOverlay) {
      return visibleAnimatedLayer;
    }

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Positioned.fill(
          child: _SelectableInlineTextOverlay(
            tokens: tokens,
            baseStyle: resolvedStyle,
            footnoteNumbers: footnoteNumbers,
            textScaler: MediaQuery.textScalerOf(context),
            selectionColor:
                markdownTheme.selectionColor ?? const Color(0x6658A6FF),
            onLinkTap: (String url) => _onLinkPressed(context, url),
          ),
        ),
        SelectionContainer.disabled(
          child: IgnorePointer(child: visibleAnimatedLayer),
        ),
      ],
    );
  }
}

extension _StreamingMarkdownLinkActions on StreamingMarkdownRenderView {
  void _onLinkPressed(BuildContext context, String url) {
    final ValueChanged<String>? callback = onLinkTap;
    if (callback != null) {
      callback(url);
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied link: $url')));
  }
}
