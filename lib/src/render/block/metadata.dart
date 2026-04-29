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
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < definitions.length; i++) {
      final _FootnoteDefinition definition = definitions[i];
      children.add(
        _buildFootnoteDefinitionLine(
          context,
          definition,
          tokenStartIndex: tokenStartIndex,
          bodyStyle: bodyStyle,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
        ),
      );
      tokenStartIndex += _countAnimatedTokenUnits(
        definition.body,
        linkReferences: linkReferences,
      );
      if (i < definitions.length - 1) {
        children.add(const SizedBox(height: 4));
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

    final List<InlineSpan> spans = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
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
          child: Text('${definition.id}: ', style: labelStyle),
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
    );

    return RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(style: bodyStyle, children: spans),
    );
  }
}
