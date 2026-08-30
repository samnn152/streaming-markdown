part of '../view.dart';

extension _StreamingMarkdownMetadataRenderer on StreamingMarkdownRenderView {
  Widget _buildMetadataBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final String text = _normalizedRaw(node.raw).trim().isNotEmpty
        ? _normalizedRaw(node.raw).trim()
        : _contentOrRaw(node);
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: markdownTheme.metadataBackgroundColor ?? const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: markdownTheme.metadataBorderColor ?? const Color(0xFF30363D),
        ),
      ),
      child: _buildInlineMarkdown(
        context,
        text,
        baseStyle: markdownTheme.metadataTextStyle ??
            const TextStyle(
              color: Color(0xFFF0F6FC),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      ),
    );
  }

  Widget _buildFootnoteDefinitionBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final List<_FootnoteDefinition> definitions =
        _parseFootnoteDefinitions(node.raw);
    if (definitions.isEmpty) {
      return _buildMetadataBlock(
        context,
        node,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
    }

    final TextStyle bodyStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    int tokenStartIndex = 0;
    int plainTextStart = 0;
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < definitions.length; i++) {
      final _FootnoteDefinition definition = definitions[i];
      children.add(
        _buildFootnoteDefinitionLine(
          context,
          definition,
          tokenStartIndex: tokenStartIndex,
          plainTextStart: plainTextStart,
          bodyStyle: bodyStyle,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        ),
      );
      tokenStartIndex += _countAnimatedTokenUnits(
        definition.body,
        linkReferences: linkReferences,
      );
      plainTextStart += '${definition.id}: '.length +
          _inlineSelectionPlainTextLength(
            definition.body,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          );
      if (i < definitions.length - 1) {
        children.add(const SizedBox(height: 4));
        plainTextStart += 1;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildFootnoteDefinitionLine(
    BuildContext context,
    _FootnoteDefinition definition, {
    required int tokenStartIndex,
    required int plainTextStart,
    required TextStyle bodyStyle,
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final TextStyle labelStyle = bodyStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: const Color(0xFF8B949E),
    );
    final List<_InlineToken> tokens = _parseInlineTokens(
      definition.body.replaceAll('\r', ''),
      references: linkReferences,
      allowUnclosedDelimiters: allowUnclosedInlineDelimiters,
    );
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenArrivalDelay;
    final String label = '${definition.id}: ';
    final String bodyPlainText = _plainTextForVisualInlineTokens(
      tokens,
      footnoteNumbers: footnoteNumbers,
    );
    final String plainText = '$label$bodyPlainText';

    final List<InlineSpan> spans = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _MarkdownSelectableTextSpan(
          semanticRange: TextRange(start: 0, end: label.length),
          text: label,
          child: _FadeInTokenHost(
            key: ValueKey<String>(
              'footnote_label_${definition.id}_$tokenStartIndex',
            ),
            initialDelay: tokenScheduleOrigin == null
                ? resolvedTokenStep * tokenStartIndex
                : Duration.zero,
            scheduledStart: tokenScheduleOrigin?.add(
              resolvedTokenStep * tokenStartIndex,
            ),
            duration: tokenFadeDuration,
            curve: tokenFadeInCurve,
            animationBuilder: tokenAnimationBuilder,
            onFadeInEnd: onTokenFadeInEnd,
            child: Text(label, style: labelStyle),
          ),
        ),
      ),
    ];
    _appendAnimatedInlineTokenSpans(
      context,
      spans: spans,
      tokens: tokens,
      baseStyle: bodyStyle,
      tokenStartIndex: tokenStartIndex,
      fadeDuration: tokenFadeDuration,
      tokenStaggerDelay: resolvedTokenStep,
      tokenScheduleOrigin: tokenScheduleOrigin,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
      plainTextOffset: label.length,
    );

    final _MarkdownTextScale textScale = _markdownTextScaleOf(context);
    final TextSpan visualText = TextSpan(style: bodyStyle, children: spans);
    final Widget animatedRichText = _markdownRichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScale: textScale,
      text: visualText,
    );
    if (!enableTextSelection) {
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: animatedRichText,
      );
    }
    final _MarkdownSelectionBlockRange? blockRange =
        _MarkdownSelectionBlockVisualScope.maybeOf(context)?.blockRange;
    final int absoluteStart =
        (blockRange?.plainRange.start ?? 0) + plainTextStart;
    final int compactStart =
        (blockRange?.compactRange.start ?? 0) + plainTextStart;
    final TextSpan selectionText = TextSpan(
      style: bodyStyle,
      children: <InlineSpan>[
        TextSpan(text: label, style: labelStyle),
        _selectionTextSpanForInlineTokens(
          tokens,
          bodyStyle,
          footnoteNumbers: footnoteNumbers,
        ),
      ],
    );
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: _SelectableInlineTextProxy(
        plainText: plainText,
        absolutePlainTextStart: absoluteStart,
        compactPlainTextStart: compactStart,
        text: selectionText,
        textDirection: TextDirection.ltr,
        textScale: textScale,
        selectionColor: markdownTheme.selectionColor ?? const Color(0x6658A6FF),
        registrar: SelectionContainer.maybeOf(context),
        selectionRegistry:
            _MarkdownInlineSelectionRegistryScope.maybeOf(context),
        child: SelectionContainer.disabled(child: animatedRichText),
      ),
    );
  }
}
