part of '../view.dart';

extension _StreamingMarkdownBlockWidgets on StreamingMarkdownRenderView {
  Widget _buildListBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final _ParsedList parsed = _parseListNode(node);
    if (parsed.items.isEmpty) {
      return _buildParagraphBlock(
        context,
        _contentOrRaw(node),
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      );
    }

    final TextStyle baseStyle = markdownTheme.paragraphTextStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenArrivalDelay;
    int tokenStartIndex = 0;
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < parsed.items.length; i++) {
      final _ParsedListItem item = parsed.items[i];
      final Widget itemRow = Padding(
        key: ValueKey<String>('list_item_${item.stableKey}'),
        padding: EdgeInsets.only(left: item.level * 18.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: _FadeInTokenHost(
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
                child: _buildListMarker(item, baseStyle),
              ),
            ),
            Expanded(
              child: _buildInlineMarkdown(
                context,
                item.text,
                tokenStartIndex: tokenStartIndex,
                baseStyle: baseStyle,
                linkReferences: linkReferences,
                footnoteNumbers: footnoteNumbers,
              ),
            ),
          ],
        ),
      );
      children.add(
        _TokenLayoutGate(
          initialDelay: tokenScheduleOrigin == null
              ? resolvedTokenStep * tokenStartIndex
              : Duration.zero,
          scheduledStart: tokenScheduleOrigin?.add(
            resolvedTokenStep * tokenStartIndex,
          ),
          child: itemRow,
        ),
      );
      tokenStartIndex += _countAnimatedTokenUnits(
        item.text,
        linkReferences: linkReferences,
      );
      if (i < parsed.items.length - 1) {
        children.add(const SizedBox(height: 4));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildQuoteBlock(
    BuildContext context,
    MarkdownRenderNode node, {
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final String text = _quoteText(node);
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final _CalloutData? callout = _parseCallout(text);
    final Color calloutColor = _calloutColor(callout?.kind);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: calloutColor, width: 3)),
        color: markdownTheme.quoteBackgroundColor ?? const Color(0xFF161B22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (callout != null) ...[
            Row(
              children: [
                Icon(_calloutIcon(callout.kind), size: 16, color: calloutColor),
                const SizedBox(width: 6),
                Text(
                  callout.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: calloutColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          _buildInlineMarkdown(
            context,
            callout?.body ?? text,
            baseStyle: markdownTheme.paragraphTextStyle ??
                Theme.of(context).textTheme.bodyLarge,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, MarkdownRenderNode node) {
    final String code = _codeText(node);
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }

    final String language = _codeLanguage(node.raw);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color:
            markdownTheme.codeBlockBackgroundColor ?? const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: markdownTheme.codeBlockHeaderBackgroundColor ??
                    const Color(0xFF161B22),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Text(
                language,
                style: markdownTheme.codeBlockLanguageTextStyle ??
                    const TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildAnimatedCodeText(context, code),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedCodeText(BuildContext context, String code) {
    final TextStyle style = markdownTheme.codeBlockTextStyle ??
        const TextStyle(
          color: Color(0xFFE6EDF3),
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
        );
    final Duration tokenFadeDuration = _resolvedTokenFadeInDuration();
    final Duration tokenStaggerDelay = tokenArrivalDelay;
    final _RevealScheduleScope? scheduleScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final DateTime? tokenScheduleOrigin = scheduleScope?.revealedAt;
    final Duration resolvedTokenStep =
        scheduleScope?.tokenArrivalDelay ?? tokenStaggerDelay;

    final List<InlineSpan> spans = <InlineSpan>[];
    _appendTokenizedTextSpans(
      spans: spans,
      text: code,
      style: style,
      startTokenIndex: 0,
      fadeDuration: tokenFadeDuration,
      fadeCurve: tokenFadeInCurve,
      tokenStaggerDelay: resolvedTokenStep,
      tokenScheduleOrigin: tokenScheduleOrigin,
      tokenAnimationBuilder: tokenAnimationBuilder,
      animatePerWord: true,
    );

    return RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(style: style, children: spans),
    );
  }
}
