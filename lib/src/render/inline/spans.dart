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
    int plainTextOffset = 0,
  }) {
    final bool compacted = _TokenCompactionScope.isCompacted(context);
    int visualTokenIndex = tokenStartIndex;
    int selectableTextStart = plainTextOffset;
    for (final _InlineToken token in tokens) {
      final String tokenPlainText = _plainTextForVisualInlineToken(
        token,
        footnoteNumbers: footnoteNumbers,
      );
      final int selectableTextEnd = selectableTextStart + tokenPlainText.length;
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
          alignment: inlineImageAlignment,
          baseline: _baselineForPlaceholderAlignment(inlineImageAlignment),
          child: _MarkdownSelectableAtomicSpan(
            semanticRange: TextRange(
              start: selectableTextStart,
              end: selectableTextEnd,
            ),
            child: _buildInlineImageToken(context, token, baseStyle),
          ),
        );
        selectableTextStart = selectableTextEnd;
        continue;
      }
      if (token.isLatex) {
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
          child: _MarkdownSelectableAtomicSpan(
            semanticRange: TextRange(
              start: selectableTextStart,
              end: selectableTextEnd,
            ),
            child: _buildLatexToken(context, token, baseStyle),
          ),
        );
        selectableTextStart = selectableTextEnd;
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
          selectableRange: TextRange(
            start: selectableTextStart,
            end: selectableTextEnd,
          ),
          selectableText:
              footnoteNumber?.toString() ?? token.footnoteReferenceId!,
          child: Text(
            footnoteNumber?.toString() ?? token.footnoteReferenceId!,
            style: baseStyle.copyWith(
              color: const Color(0xFF8B949E),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        selectableTextStart = selectableTextEnd;
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
          plainTextOffset: selectableTextStart,
          onTap: enableTextSelection
              ? null
              : () => _onLinkPressed(context, token.linkUrl!),
        );
        selectableTextStart = selectableTextEnd;
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
        plainTextOffset: selectableTextStart,
      );
      selectableTextStart = selectableTextEnd;
    }
  }

  Widget _buildImageBlock(BuildContext context, _InlineImageMatch image) {
    final Widget imageWidget = _MarkdownNetworkImage(
      url: image.url,
      altText: image.alt,
      inline: false,
      imageBuilder: customImageBuilder,
      fallbackWidget: _buildBlockImageFallback(),
      loadedBuilder: (ImageInfo imageInfo, Size intrinsicSize) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: RawImage(
                image: imageInfo.image,
                scale: imageInfo.scale,
                fit: BoxFit.contain,
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
      },
    );
    final TextStyle semanticStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    return _buildSelectableAtomicContent(
      context,
      plainText: image.alt.isEmpty ? '[image]' : '[image: ${image.alt}]',
      textStyle: semanticStyle,
      child: imageWidget,
    );
  }

  Widget _buildDisplayLatexBlock(
    BuildContext context,
    _LatexMatch latex,
    TextStyle baseStyle,
  ) {
    final Widget math = _buildLatexWidget(
      context,
      expression: latex.expression,
      sourceMarkdown: latex.sourceMarkdown,
      display: true,
      baseStyle: baseStyle,
    );
    final Widget displayWidget = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: math,
      ),
    );
    return _buildSelectableAtomicContent(
      context,
      plainText: latex.sourceMarkdown,
      textStyle: baseStyle,
      child: displayWidget,
    );
  }

  Widget _buildSelectableAtomicContent(
    BuildContext context, {
    required String plainText,
    required TextStyle textStyle,
    required Widget child,
    int plainTextStart = 0,
  }) {
    if (!enableTextSelection || plainText.isEmpty) {
      return child;
    }
    final _MarkdownSelectionBlockRange? selectionBlockRange =
        _MarkdownSelectionBlockVisualScope.maybeOf(context)?.blockRange;
    final int absoluteBlockStart = selectionBlockRange?.plainRange.start ?? 0;
    final int compactBlockStart =
        selectionBlockRange?.compactRange.start ?? absoluteBlockStart;
    final int absolutePlainTextStart = absoluteBlockStart + plainTextStart;
    final int compactPlainTextStart = compactBlockStart + plainTextStart;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: _SelectableInlineTextProxy(
        plainText: plainText,
        absolutePlainTextStart: absolutePlainTextStart,
        compactPlainTextStart: compactPlainTextStart,
        text: TextSpan(text: plainText, style: textStyle),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScale: _markdownTextScaleOf(context),
        selectionColor: markdownTheme.selectionColor ?? const Color(0x6658A6FF),
        registrar: SelectionContainer.maybeOf(context),
        selectionRegistry:
            _MarkdownInlineSelectionRegistryScope.maybeOf(context),
        atomic: true,
        child: SelectionContainer.disabled(child: child),
      ),
    );
  }

  Widget _buildLatexToken(
    BuildContext context,
    _InlineToken token,
    TextStyle baseStyle,
  ) {
    return _buildLatexWidget(
      context,
      expression: token.latexExpression ?? '',
      sourceMarkdown: token.sourceMarkdown,
      display: token.latexDisplay,
      baseStyle: baseStyle,
    );
  }

  Widget _buildLatexWidget(
    BuildContext context, {
    required String expression,
    required String sourceMarkdown,
    required bool display,
    required TextStyle baseStyle,
  }) {
    final TextStyle fallbackStyle =
        markdownTheme.latexErrorTextStyle ?? baseStyle;
    final Widget fallbackWidget = Text(sourceMarkdown, style: fallbackStyle);
    final TextStyle mathStyle = (display
            ? markdownTheme.displayLatexTextStyle
            : markdownTheme.inlineLatexTextStyle) ??
        baseStyle;
    final String normalizedExpression = _normalizeLatexExpression(expression);
    final Key latexKey = ValueKey<String>(
      'latex:${display ? 'display' : 'inline'}:$normalizedExpression',
    );
    final Widget math = RepaintBoundary(
      key: latexKey,
      child: Math.tex(
        normalizedExpression,
        key: latexKey,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        textStyle: mathStyle,
        onErrorFallback: (_) => fallbackWidget,
      ),
    );
    final Widget defaultWidget = display
        ? math
        : ClipRect(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: math,
            ),
          );
    final StreamingMarkdownLatexBuilder? builder = customLatexBuilder;
    if (builder == null) {
      return defaultWidget;
    }
    return builder(
      context,
      StreamingMarkdownLatexBuildContext(
        expression: expression,
        sourceMarkdown: sourceMarkdown,
        display: display,
        defaultWidget: defaultWidget,
        fallbackWidget: fallbackWidget,
      ),
    );
  }

  String _normalizeLatexExpression(String expression) {
    return expression
        .replaceAll(r'\left|', r'\vert')
        .replaceAll(r'\right|', r'\vert');
  }

  Widget _buildInlineImageToken(
    BuildContext context,
    _InlineToken token,
    TextStyle baseStyle,
  ) {
    final String? imageUrl = token.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return _buildInlineImageFallback(token, baseStyle);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: _MarkdownNetworkImage(
        url: imageUrl,
        altText: token.altText,
        inline: true,
        imageBuilder: customImageBuilder,
        fallbackWidget: _buildInlineImageFallback(token, baseStyle),
        loadedBuilder: (ImageInfo imageInfo, Size intrinsicSize) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: RawImage(
              image: imageInfo.image,
              scale: imageInfo.scale,
              width: intrinsicSize.width,
              height: intrinsicSize.height,
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBlockImageFallback() {
    return Container(
      height: 120,
      width: double.infinity,
      color: markdownTheme.imageErrorBackgroundColor ?? const Color(0xFF161B22),
      alignment: Alignment.center,
      child: Text(
        'Image unavailable',
        style: markdownTheme.imageErrorTextStyle ??
            const TextStyle(color: Color(0xFFF0F6FC)),
      ),
    );
  }

  Widget _buildInlineImageFallback(_InlineToken token, TextStyle baseStyle) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:
            markdownTheme.imageErrorBackgroundColor ?? const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Text(
        token.altText.isEmpty ? 'image' : 'image: ${token.altText}',
        style: markdownTheme.imageErrorTextStyle ??
            baseStyle.copyWith(
              color: const Color(0xFFF0F6FC),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
      ),
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

  TextBaseline? _baselineForPlaceholderAlignment(
    PlaceholderAlignment alignment,
  ) {
    switch (alignment) {
      case PlaceholderAlignment.aboveBaseline:
      case PlaceholderAlignment.belowBaseline:
      case PlaceholderAlignment.baseline:
        return TextBaseline.alphabetic;
      case PlaceholderAlignment.top:
      case PlaceholderAlignment.bottom:
      case PlaceholderAlignment.middle:
        return null;
    }
  }
}

typedef _LoadedImageBuilder = Widget Function(
  ImageInfo imageInfo,
  Size intrinsicSize,
);

class _MarkdownImageLoadBarrier extends StatefulWidget {
  const _MarkdownImageLoadBarrier({
    required this.urls,
    required this.child,
  });

  final List<String> urls;
  final Widget child;

  @override
  State<_MarkdownImageLoadBarrier> createState() =>
      _MarkdownImageLoadBarrierState();
}

class _MarkdownImageLoadBarrierState extends State<_MarkdownImageLoadBarrier> {
  final Map<String, ImageStream> _streams = <String, ImageStream>{};
  final Map<String, ImageStreamListener> _listeners =
      <String, ImageStreamListener>{};
  final Set<String> _resolved = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImages();
  }

  @override
  void didUpdateWidget(covariant _MarkdownImageLoadBarrier oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameUrlSet(oldWidget.urls, widget.urls)) {
      _resolveImages();
    }
  }

  @override
  void dispose() {
    _removeListeners();
    super.dispose();
  }

  void _resolveImages() {
    _removeListeners();
    _resolved.clear();

    final Set<String> urls = widget.urls.toSet();
    if (urls.isEmpty) {
      return;
    }
    for (final String url in urls) {
      final ImageStream stream = NetworkImage(url).resolve(
        createLocalImageConfiguration(context),
      );
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo imageInfo, bool synchronousCall) {
          _markResolved(url);
        },
        onError: (Object error, StackTrace? stackTrace) {
          _markResolved(url);
        },
      );
      _streams[url] = stream;
      _listeners[url] = listener;
      stream.addListener(listener);
    }
  }

  void _markResolved(String url) {
    if (!mounted || _resolved.contains(url)) {
      return;
    }
    setState(() {
      _resolved.add(url);
    });
  }

  void _removeListeners() {
    for (final MapEntry<String, ImageStreamListener> entry
        in _listeners.entries) {
      _streams[entry.key]?.removeListener(entry.value);
    }
    _streams.clear();
    _listeners.clear();
  }

  bool _sameUrlSet(List<String> a, List<String> b) {
    return a.toSet().containsAll(b) && b.toSet().containsAll(a);
  }

  @override
  Widget build(BuildContext context) {
    if (_resolved.length < widget.urls.toSet().length) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}

class _MarkdownNetworkImage extends StatefulWidget {
  const _MarkdownNetworkImage({
    required this.url,
    required this.altText,
    required this.inline,
    required this.imageBuilder,
    required this.fallbackWidget,
    required this.loadedBuilder,
  });

  final String url;
  final String altText;
  final bool inline;
  final StreamingMarkdownImageBuilder? imageBuilder;
  final Widget fallbackWidget;
  final _LoadedImageBuilder loadedBuilder;

  @override
  State<_MarkdownNetworkImage> createState() => _MarkdownNetworkImageState();
}

class _MarkdownNetworkImageState extends State<_MarkdownNetworkImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _MarkdownNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _imageInfo = null;
      _error = null;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  void _resolveImage() {
    _removeListener();
    if (widget.url.isEmpty) {
      _error = StateError('Image URL is empty');
      return;
    }

    final ImageProvider provider = NetworkImage(widget.url);
    final ImageStream stream = provider.resolve(
      createLocalImageConfiguration(context),
    );
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        if (!mounted) {
          return;
        }
        setState(() {
          _imageInfo = imageInfo;
          _error = null;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) {
          return;
        }
        setState(() {
          _imageInfo = null;
          _error = error;
        });
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _removeListener() {
    final ImageStream? stream = _stream;
    final ImageStreamListener? listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final Widget defaultWidget;
    final StreamingMarkdownImageState state;
    final Size? intrinsicSize;

    final ImageInfo? imageInfo = _imageInfo;
    if (imageInfo != null) {
      intrinsicSize = Size(
        imageInfo.image.width / imageInfo.scale,
        imageInfo.image.height / imageInfo.scale,
      );
      defaultWidget = widget.loadedBuilder(imageInfo, intrinsicSize);
      state = StreamingMarkdownImageState.loaded;
    } else if (_error != null) {
      intrinsicSize = null;
      defaultWidget = widget.fallbackWidget;
      state = StreamingMarkdownImageState.error;
    } else {
      intrinsicSize = null;
      defaultWidget = const SizedBox.shrink();
      state = StreamingMarkdownImageState.loading;
    }

    final StreamingMarkdownImageBuilder? builder = widget.imageBuilder;
    if (builder == null) {
      return defaultWidget;
    }
    return builder(
      context,
      StreamingMarkdownImageBuildContext(
        url: widget.url,
        altText: widget.altText,
        inline: widget.inline,
        state: state,
        intrinsicSize: intrinsicSize,
        defaultWidget: defaultWidget,
        fallbackWidget: widget.fallbackWidget,
        error: _error,
      ),
    );
  }
}
