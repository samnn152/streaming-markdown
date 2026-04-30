part of '../view.dart';

extension _StreamingMarkdownInlineSpanRenderer on StreamingMarkdownRenderView {
  void _appendAnimatedInlineTokenSpans(
    BuildContext context, {
    required List<InlineSpan> spans,
    required List<_InlineToken> tokens,
    required TextStyle baseStyle,
    required int tokenStartIndex,
    required Duration fadeDuration,
    required Duration tokenStaggerDelay,
    required DateTime? tokenScheduleOrigin,
    required Map<String, String> linkReferences,
    required Map<String, int> footnoteNumbers,
  }) {
    final bool compacted = _TokenCompactionScope.isCompacted(context);
    int visualTokenIndex = tokenStartIndex;
    for (final _InlineToken token in tokens) {
      if (token.isImage) {
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: fadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: tokenStaggerDelay,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.middle,
          child: Text(
            token.altText.isEmpty ? '[image]' : '[image: ${token.altText}]',
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
        continue;
      }
      if (token.isFootnoteReference) {
        final int? footnoteNumber = _footnoteNumberForId(
          footnoteNumbers,
          token.footnoteReferenceId!,
        );
        visualTokenIndex = _appendAnimatedWidgetSpan(
          spans: spans,
          tokenIndex: visualTokenIndex,
          fadeDuration: fadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: tokenStaggerDelay,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animate: !compacted,
          alignment: PlaceholderAlignment.aboveBaseline,
          baseline: TextBaseline.alphabetic,
          child: Text(
            footnoteNumber?.toString() ?? token.footnoteReferenceId!,
            style: baseStyle.copyWith(
              color: const Color(0xFF8B949E),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        continue;
      }

      TextStyle style = baseStyle;
      if (token.style.bold) {
        style = style.copyWith(fontWeight: FontWeight.w700);
      }
      if (token.style.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
      if (token.style.strikethrough) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (token.style.code) {
        style = markdownTheme.inlineCodeTextStyle ??
            style.copyWith(fontFamily: 'monospace', fontSize: 12);
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
          fadeDuration: fadeDuration,
          fadeCurve: tokenFadeInCurve,
          tokenStaggerDelay: tokenStaggerDelay,
          tokenScheduleOrigin: tokenScheduleOrigin,
          tokenAnimationBuilder: tokenAnimationBuilder,
          animatePerWord: !compacted,
          onTap: enableTextSelection
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
        fadeDuration: fadeDuration,
        fadeCurve: tokenFadeInCurve,
        tokenStaggerDelay: tokenStaggerDelay,
        tokenScheduleOrigin: tokenScheduleOrigin,
        tokenAnimationBuilder: tokenAnimationBuilder,
        animatePerWord: !compacted,
      );
    }
  }

  Widget _buildImageBlock(BuildContext context, _InlineImageMatch image) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            image.url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              width: double.infinity,
              color: markdownTheme.imageErrorBackgroundColor ??
                  const Color(0xFF161B22),
              alignment: Alignment.center,
              child: Text(
                'Image unavailable',
                style: markdownTheme.imageErrorTextStyle ??
                    const TextStyle(color: Color(0xFFF0F6FC)),
              ),
            ),
          ),
        ),
        if (image.alt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            image.alt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8B949E),
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildListMarker(_ParsedListItem item, TextStyle baseStyle) {
    if (item.taskState != null) {
      return SizedBox(
        height: _listMarkerLineHeight(baseStyle),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            item.taskState! ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: item.taskState!
                ? const Color(0xFF2EA043)
                : const Color(0xFF8B949E),
          ),
        ),
      );
    }
    if (item.ordered) {
      return Text('${item.order}.', style: baseStyle);
    }
    return Text('•', style: baseStyle);
  }

  double _listMarkerLineHeight(TextStyle baseStyle) {
    final double fontSize = baseStyle.fontSize ?? 16;
    final double height = baseStyle.height ?? 1.5;
    return fontSize * height;
  }
}
