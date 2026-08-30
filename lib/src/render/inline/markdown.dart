part of '../view.dart';

extension _StreamingMarkdownInlineMarkdownRenderer
    on StreamingMarkdownRenderView {
  Widget _buildInlineMarkdown(
    BuildContext context,
    String text, {
    int tokenStartIndex = 0,
    int plainTextStart = 0,
    bool restrictSelectionToRevealedTokens = false,
    TextStyle? baseStyle,
    Map<String, String> linkReferences = const <String, String>{},
    Map<String, int> footnoteNumbers = const <String, int>{},
    SelectionRegistrar? customRegistrar,
  }) {
    final String normalized = text.replaceAll('\r', '');
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final TextStyle resolvedStyle = baseStyle ??
        markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
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
    final String selectableText = _plainTextForVisualInlineTokens(
      tokens,
      footnoteNumbers: footnoteNumbers,
    );
    final TextSpan selectionText = _selectionTextSpanForInlineTokens(
      tokens,
      resolvedStyle,
      footnoteNumbers: footnoteNumbers,
    );
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final Duration tokenStaggerDelay = tokenArrivalDelay;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenStaggerDelay;
    final _InlineSelectionRevealController? selectionRevealController =
        restrictSelectionToRevealedTokens &&
                enableTextSelection &&
                animatePerWord &&
                tokenFadeDuration > Duration.zero &&
                resolvedTokenStep > Duration.zero
            ? _InlineSelectionRevealController()
            : null;
    final ValueChanged<int>? onTokenReveal =
        selectionRevealController?.revealThrough;
    // Selection is painted once by the selectable proxy. Painting it inside
    // every animated token creates a separate backdrop for each word and makes
    // a continuous browser-style selection look like a row of shadows.
    //
    // The proxy owns a stable coordinator-backed paint range, so it can keep
    // this single layer alive through framework geometry repartitioning and
    // sliver remounts without rebuilding the token subtree.
    final Color flatSelectionColor =
        markdownTheme.selectionColor ?? const Color(0x6658A6FF);

    final List<InlineSpan> spans = <InlineSpan>[];
    int visualTokenIndex = tokenStartIndex;
    int selectableTokenTextStart = 0;
    for (final _InlineToken token in tokens) {
      final String tokenSelectableText = _plainTextForVisualInlineToken(
        token,
        footnoteNumbers: footnoteNumbers,
      );
      final int tokenSelectableTextEnd =
          selectableTokenTextStart + tokenSelectableText.length;
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
          alignment: inlineImageAlignment,
          baseline: _baselineForPlaceholderAlignment(inlineImageAlignment),
          revealedTextEnd: tokenSelectableTextEnd,
          onTokenReveal: onTokenReveal,
          child: _MarkdownSelectableAtomicSpan(
            semanticRange: TextRange(
              start: selectableTokenTextStart,
              end: tokenSelectableTextEnd,
            ),
            child: _buildInlineImageToken(context, token, resolvedStyle),
          ),
        );
        selectableTokenTextStart = tokenSelectableTextEnd;
        continue;
      }

      if (token.isLatex) {
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
          revealedTextEnd: tokenSelectableTextEnd,
          onTokenReveal: onTokenReveal,
          child: _MarkdownSelectableAtomicSpan(
            semanticRange: TextRange(
              start: selectableTokenTextStart,
              end: tokenSelectableTextEnd,
            ),
            child: _buildLatexToken(context, token, resolvedStyle),
          ),
        );
        selectableTokenTextStart = tokenSelectableTextEnd;
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
          revealedTextEnd: tokenSelectableTextEnd,
          onTokenReveal: onTokenReveal,
          selectableRange: TextRange(
            start: selectableTokenTextStart,
            end: tokenSelectableTextEnd,
          ),
          selectableText: token.text,
          paintFullSelectionBounds: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _MarkdownSelectionAwareBackground(
              text: token.text,
              color: markdownTheme.inlineCodeBackgroundColor ??
                  const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(token.text, style: inlineCodeStyle),
              ),
            ),
          ),
        );
        selectableTokenTextStart = tokenSelectableTextEnd;
        continue;
      }

      if (token.isFootnoteReference) {
        final int? footnoteNumber = _footnoteNumberForId(
          footnoteNumbers,
          token.footnoteReferenceId!,
        );
        final String label =
            footnoteNumber?.toString() ?? token.footnoteReferenceId!;
        const TextStyle footnoteStyle = TextStyle(
          color: Color(0xFF8B949E),
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
          alignment: PlaceholderAlignment.aboveBaseline,
          baseline: TextBaseline.alphabetic,
          revealedTextEnd: tokenSelectableTextEnd,
          onTokenReveal: onTokenReveal,
          selectableRange: TextRange(
            start: selectableTokenTextStart,
            end: tokenSelectableTextEnd,
          ),
          selectableText: label,
          child: Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Text(label, style: footnoteStyle),
          ),
        );
        selectableTokenTextStart = tokenSelectableTextEnd;
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
          plainTextOffset: selectableTokenTextStart,
          onTokenReveal: onTokenReveal,
          onTap: () => _onLinkPressed(context, token.linkUrl!),
        );
        selectableTokenTextStart = tokenSelectableTextEnd;
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
        plainTextOffset: selectableTokenTextStart,
        onTokenReveal: onTokenReveal,
      );
      selectableTokenTextStart = tokenSelectableTextEnd;
    }

    final _MarkdownTextScale textScale = _markdownTextScaleOf(context);
    final _MarkdownSelectionBlockRange? selectionBlockRange =
        _MarkdownSelectionBlockVisualScope.maybeOf(context)?.blockRange;
    final int absolutePlainTextStart =
        (selectionBlockRange?.plainRange.start ?? 0) + plainTextStart;
    final int compactPlainTextStart =
        (selectionBlockRange?.compactRange.start ?? absolutePlainTextStart) +
            plainTextStart;
    final _MarkdownInlineSelectionRegistry? inlineSelectionRegistry =
        _MarkdownInlineSelectionRegistryScope.maybeOf(context);
    final Widget animatedRichText = _markdownRichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScale: textScale,
      text: TextSpan(style: resolvedStyle, children: spans),
    );
    final Widget selectionChild =
        SelectionContainer.disabled(child: animatedRichText);
    final Widget selectableOutput = !enableTextSelection
        ? animatedRichText
        : selectionRevealController == null
            ? _SelectableInlineTextProxy(
                plainText: selectableText,
                absolutePlainTextStart: absolutePlainTextStart,
                compactPlainTextStart: compactPlainTextStart,
                text: selectionText,
                textDirection: TextDirection.ltr,
                textScale: textScale,
                selectionColor: flatSelectionColor,
                registrar:
                    customRegistrar ?? SelectionContainer.maybeOf(context),
                selectionRegistry: inlineSelectionRegistry,
                child: selectionChild,
              )
            : _ProgressiveSelectableInlineTextProxy(
                revealController: selectionRevealController,
                plainText: selectableText,
                absolutePlainTextStart: absolutePlainTextStart,
                compactPlainTextStart: compactPlainTextStart,
                text: selectionText,
                textDirection: TextDirection.ltr,
                textScale: textScale,
                selectionColor: flatSelectionColor,
                registrar:
                    customRegistrar ?? SelectionContainer.maybeOf(context),
                selectionRegistry: inlineSelectionRegistry,
                child: selectionChild,
              );
    final Widget output = MouseRegion(
      cursor: SystemMouseCursors.text,
      child: selectableOutput,
    );

    final List<String> inlineImageUrls = tokens
        .where((_InlineToken token) => token.isImage)
        .map((_InlineToken token) => token.imageUrl ?? '')
        .where((String url) => url.isNotEmpty)
        .toList(growable: false);
    if (inlineImageUrls.isEmpty || customImageBuilder != null) {
      return output;
    }
    return _MarkdownImageLoadBarrier(urls: inlineImageUrls, child: output);
  }
}

String _plainTextForVisualInlineTokens(
  List<_InlineToken> tokens, {
  required Map<String, int> footnoteNumbers,
}) {
  final StringBuffer buffer = StringBuffer();
  for (final _InlineToken token in tokens) {
    buffer.write(
      _plainTextForVisualInlineToken(
        token,
        footnoteNumbers: footnoteNumbers,
      ),
    );
  }
  return buffer.toString();
}

TextSpan _selectionTextSpanForInlineTokens(
  List<_InlineToken> tokens,
  TextStyle baseStyle, {
  required Map<String, int> footnoteNumbers,
}) {
  final List<InlineSpan> spans = <InlineSpan>[];
  for (final _InlineToken token in tokens) {
    TextStyle style = baseStyle;
    if (token.style.bold) {
      style = style.copyWith(fontWeight: FontWeight.w700);
    }
    if (token.style.italic) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (token.style.code) {
      style = style.copyWith(fontFamily: 'monospace', fontSize: 12);
    }
    spans.add(
      TextSpan(
        text: _plainTextForVisualInlineToken(
          token,
          footnoteNumbers: footnoteNumbers,
        ),
        style: style,
      ),
    );
  }
  return TextSpan(style: baseStyle, children: spans);
}

String _plainTextForVisualInlineToken(
  _InlineToken token, {
  required Map<String, int> footnoteNumbers,
}) {
  if (token.isImage) {
    return token.altText.isEmpty ? '[image]' : '[image: ${token.altText}]';
  }
  if (token.isFootnoteReference) {
    final int? number = _footnoteNumberForId(
      footnoteNumbers,
      token.footnoteReferenceId!,
    );
    return number?.toString() ?? token.footnoteReferenceId!;
  }
  if (token.isLatex) {
    return token.sourceMarkdown;
  }
  return token.text;
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
