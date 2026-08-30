part of 'view.dart';

/// Custom builder hook for overriding a rendered markdown block widget.
typedef StreamingMarkdownBlockBuilder = Widget? Function(
  BuildContext context,
  StreamingMarkdownBlockBuildContext block,
);

/// Snapshot passed into [StreamingMarkdownTokenAnimationBuilder].
@immutable
class StreamingMarkdownAnimatedToken {
  /// Creates a token animation snapshot.
  const StreamingMarkdownAnimatedToken({
    required this.child,
    required this.animation,
  });

  /// Widget that renders the token content.
  final Widget child;

  /// Animation value for this token, usually from `0.0` to `1.0`.
  final Animation<double> animation;

  /// Current animation value.
  double get value => animation.value;
}

/// Preferred public name for a token animation snapshot.
typedef AnimatedMarkdownToken = StreamingMarkdownAnimatedToken;

/// Custom animation hook for each rendered token.
typedef StreamingMarkdownTokenAnimationBuilder = Widget Function(
  BuildContext context,
  StreamingMarkdownAnimatedToken token,
);

/// Loading/rendering state for a markdown image.
enum StreamingMarkdownImageState {
  /// The image provider has not resolved dimensions yet.
  loading,

  /// The image loaded and [StreamingMarkdownImageBuildContext.intrinsicSize]
  /// is available.
  loaded,

  /// Loading failed.
  error,
}

/// Context passed to [StreamingMarkdownImageBuilder].
class StreamingMarkdownImageBuildContext {
  /// Creates an image build context.
  const StreamingMarkdownImageBuildContext({
    required this.url,
    required this.altText,
    required this.inline,
    required this.state,
    required this.defaultWidget,
    required this.fallbackWidget,
    this.intrinsicSize,
    this.error,
  });

  /// Image URL from markdown source.
  final String url;

  /// Alt text from markdown source.
  final String altText;

  /// Whether this image is inside a paragraph instead of a standalone block.
  final bool inline;

  /// Current image loading state.
  final StreamingMarkdownImageState state;

  /// Intrinsic logical-pixel size after the image has loaded.
  final Size? intrinsicSize;

  /// Default widget for the current state.
  final Widget defaultWidget;

  /// Standard fallback widget used when loading fails.
  final Widget fallbackWidget;

  /// Loading error when [state] is [StreamingMarkdownImageState.error].
  final Object? error;
}

/// Custom builder hook for markdown images.
typedef StreamingMarkdownImageBuilder = Widget Function(
  BuildContext context,
  StreamingMarkdownImageBuildContext image,
);

/// Context passed to [StreamingMarkdownLatexBuilder].
class StreamingMarkdownLatexBuildContext {
  /// Creates a LaTeX build context.
  const StreamingMarkdownLatexBuildContext({
    required this.expression,
    required this.sourceMarkdown,
    required this.display,
    required this.defaultWidget,
    required this.fallbackWidget,
  });

  /// TeX expression without markdown delimiters.
  final String expression;

  /// Source markdown including delimiters such as `$...$` or `$$...$$`.
  final String sourceMarkdown;

  /// Whether the expression came from a display-style delimiter.
  final bool display;

  /// Default KaTeX-compatible Flutter math widget.
  final Widget defaultWidget;

  /// Plain-text fallback used when math rendering fails or is disabled by a
  /// custom builder.
  final Widget fallbackWidget;
}

/// Custom builder hook for LaTeX math rendered with the embedded
/// KaTeX-compatible engine.
typedef StreamingMarkdownLatexBuilder = Widget Function(
  BuildContext context,
  StreamingMarkdownLatexBuildContext latex,
);

/// Preferred token animation builder name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownTokenBuilder = StreamingMarkdownTokenAnimationBuilder;

/// Preferred block override builder name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownBlockBuilder = StreamingMarkdownBlockBuilder;

/// Preferred image builder name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownImageBuilder = StreamingMarkdownImageBuilder;

/// Preferred LaTeX builder name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownLatexBuilder = StreamingMarkdownLatexBuilder;

/// Chooses the temporary visible text for an incomplete streaming link.
///
/// Returning an empty string suppresses the construct until more source
/// arrives. The default renderer shows [MarkdownInlineLink.destination] once
/// it is non-empty and otherwise returns an empty string.
typedef StreamingMarkdownIncompleteLinkTextBuilder = String Function(
  MarkdownInlineLink link,
);

/// Preferred incomplete-link projection hook for
/// [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownIncompleteLinkTextBuilder
    = StreamingMarkdownIncompleteLinkTextBuilder;

/// Adds source-backed selection geometry to a fully custom Markdown widget.
///
/// Custom image and LaTeX builders are already selectable because the renderer
/// keeps their semantic wrapper outside the builder. Use this widget when a
/// [StreamingMarkdownBlockBuilder] replaces
/// [StreamingMarkdownBlockBuildContext.defaultWidget] with a non-text object.
///
/// [plainText] must be the plain-text projection represented by [child] inside
/// the current block. [plainTextStart] locates it within that block projection.
/// The default constructor keeps the original atomic behavior. Use
/// [AnimatedMarkdownSelectable.text] for a `Text` or `SelectableText` child,
/// or [AnimatedMarkdownSelectable.fragments] with
/// [AnimatedMarkdownSelectionFragment] for a composite custom object. Copy
/// always remains backed by the coordinator's original Markdown source.
class AnimatedMarkdownSelectable extends StatelessWidget {
  /// Creates an atomic selectable wrapper for custom Markdown content.
  const AnimatedMarkdownSelectable({
    super.key,
    required this.plainText,
    required this.child,
    this.plainTextStart = 0,
    this.textStyle,
    this.selectionColor = const Color(0x6658A6FF),
  }) : _mode = _AnimatedMarkdownSelectableMode.atomic;

  /// Creates character-level selection backed by the rendered text geometry.
  ///
  /// The descendant may be Flutter's [Text], [RichText], or [SelectableText].
  /// Its visible plain text must equal [plainText]. The wrapper owns selection,
  /// so a nested `SelectableText` does not create a second independent range.
  const AnimatedMarkdownSelectable.text({
    super.key,
    required this.plainText,
    required this.child,
    this.plainTextStart = 0,
    this.textStyle,
    this.selectionColor = const Color(0x6658A6FF),
  }) : _mode = _AnimatedMarkdownSelectableMode.text;

  /// Creates character-level selection for a composite custom object.
  ///
  /// Descendant text regions declare their local offsets with
  /// [AnimatedMarkdownSelectionFragment]. Non-text descendants remain usable
  /// and the declared fragments participate in one Markdown selection.
  const AnimatedMarkdownSelectable.fragments({
    super.key,
    required this.plainText,
    required this.child,
    this.plainTextStart = 0,
    this.textStyle,
    this.selectionColor = const Color(0x6658A6FF),
  }) : _mode = _AnimatedMarkdownSelectableMode.fragments;

  /// Plain-text meaning represented by [child].
  final String plainText;

  /// Offset of [plainText] in the current block's plain-text projection.
  final int plainTextStart;

  /// Geometry style used for the hidden semantic text layout.
  final TextStyle? textStyle;

  /// Selection highlight color.
  final Color selectionColor;

  /// Custom visual content.
  final Widget child;

  final _AnimatedMarkdownSelectableMode _mode;

  @override
  Widget build(BuildContext context) {
    final _MarkdownSelectionBlockRange? blockRange =
        _MarkdownSelectionBlockVisualScope.maybeOf(context)?.blockRange;
    final SelectionRegistrar? registrar = SelectionContainer.maybeOf(context);
    if (plainText.isEmpty || blockRange == null || registrar == null) {
      return child;
    }

    final int blockPlainTextLength =
        blockRange.plainRange.end - blockRange.plainRange.start;
    final int localStart = plainTextStart.clamp(0, blockPlainTextLength);
    final int absoluteStart = blockRange.plainRange.start + localStart;
    final int compactStart = blockRange.compactRange.start + localStart;
    final TextStyle resolvedStyle =
        textStyle ?? DefaultTextStyle.of(context).style;
    Widget visualChild = child;
    if (_mode == _AnimatedMarkdownSelectableMode.text) {
      // Delegate gestures to the surrounding Markdown SelectionArea. A nested
      // RenderEditable remains available for exact character geometry, but it
      // cannot create a second independent native highlight. Composite objects
      // with interactive siblings should use the fragments constructor.
      visualChild = AbsorbPointer(child: visualChild);
      visualChild = _MarkdownSelectableTextSpan(
        semanticRange: TextRange(start: 0, end: plainText.length),
        text: plainText,
        paintSelectionLocally: true,
        child: visualChild,
      );
    } else if (_mode == _AnimatedMarkdownSelectableMode.fragments) {
      visualChild = _AnimatedMarkdownSelectionFragmentScope(
        plainTextLength: plainText.length,
        child: visualChild,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: _SelectableInlineTextProxy(
        plainText: plainText,
        absolutePlainTextStart: absoluteStart,
        compactPlainTextStart: compactStart,
        text: TextSpan(text: plainText, style: resolvedStyle),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScale: _markdownTextScaleOf(context),
        selectionColor: selectionColor,
        registrar: registrar,
        selectionRegistry:
            _MarkdownInlineSelectionRegistryScope.maybeOf(context),
        atomic: _mode == _AnimatedMarkdownSelectableMode.atomic,
        child: SelectionContainer.disabled(child: visualChild),
      ),
    );
  }
}

enum _AnimatedMarkdownSelectableMode { atomic, text, fragments }

/// Declares one character-selectable region inside
/// [AnimatedMarkdownSelectable.fragments].
class AnimatedMarkdownSelectionFragment extends StatelessWidget {
  /// Creates a fragment at [plainTextStart] in its parent projection.
  const AnimatedMarkdownSelectionFragment({
    super.key,
    required this.plainText,
    required this.plainTextStart,
    required this.child,
  });

  /// Visible text represented by [child].
  final String plainText;

  /// Local offset in the enclosing custom object's plain text.
  final int plainTextStart;

  /// Visual fragment, normally a [Text], [RichText], or [SelectableText].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _AnimatedMarkdownSelectionFragmentScope? scope =
        _AnimatedMarkdownSelectionFragmentScope.maybeOf(context);
    assert(
      scope != null,
      'AnimatedMarkdownSelectionFragment must be inside '
      'AnimatedMarkdownSelectable.fragments.',
    );
    if (scope == null || plainText.isEmpty) {
      return child;
    }
    final int start = plainTextStart.clamp(0, scope.plainTextLength);
    final int end = (start + plainText.length).clamp(
      start,
      scope.plainTextLength,
    );
    assert(
      end - start == plainText.length,
      'The fragment range must fit inside the parent plainText.',
    );
    final String representedText = plainText.substring(0, end - start);
    return _MarkdownSelectableTextSpan(
      semanticRange: TextRange(start: start, end: end),
      text: representedText,
      paintSelectionLocally: true,
      child: child,
    );
  }
}

class _AnimatedMarkdownSelectionFragmentScope extends InheritedWidget {
  const _AnimatedMarkdownSelectionFragmentScope({
    required this.plainTextLength,
    required super.child,
  });

  final int plainTextLength;

  static _AnimatedMarkdownSelectionFragmentScope? maybeOf(
    BuildContext context,
  ) {
    return context.dependOnInheritedWidgetOfExactType<
        _AnimatedMarkdownSelectionFragmentScope>();
  }

  @override
  bool updateShouldNotify(
    covariant _AnimatedMarkdownSelectionFragmentScope oldWidget,
  ) {
    return plainTextLength != oldWidget.plainTextLength;
  }
}

/// Preferred public name for block override context.
typedef AnimatedMarkdownBlockContext = StreamingMarkdownBlockBuildContext;

/// Controls whether animated word tokens shed their animation hosts after their
/// reveal animation has completed.
///
/// Compaction only changes the settled node structure: the geometry used for
/// layout and selection remains stable so a completed reveal does not reflow
/// text or move an active selection.
enum AnimatedMarkdownTokenCompaction {
  /// Keep the per-token widget spans for the lifetime of the rendered block.
  disabled,

  /// Remove settled animation hosts once the reveal has completed, while
  /// keeping token geometry stable so text wrapping does not jump.
  ///
  /// Debug-token rendering is kept expanded so token boundaries remain visible.
  automatic,

  /// Remove settled animation hosts whenever possible, including debug-token
  /// rendering.
  always,
}

/// Context object passed to [StreamingMarkdownBlockBuilder].
class StreamingMarkdownBlockBuildContext {
  const StreamingMarkdownBlockBuildContext({
    required this.node,
    required this.linkReferences,
    required this.defaultWidget,
  });

  /// Source render node for this block.
  final MarkdownRenderNode node;

  /// Source render node for this block.
  ///
  /// Prefer this name in new code. [node] remains available for compatibility
  /// with `0.2.x`.
  MarkdownRenderNode get block => node;

  /// Link reference map extracted from current node list.
  final Map<String, String> linkReferences;

  /// Default widget produced by internal renderer.
  final Widget defaultWidget;
}

/// Theme/customization data for [AnimatedStreamingMarkdown].
class StreamingMarkdownThemeData {
  /// Creates immutable rendering theme data.
  const StreamingMarkdownThemeData({
    this.blockSpacing = 12,
    this.paragraphTextStyle,
    this.heading1TextStyle,
    this.heading2TextStyle,
    this.heading3TextStyle,
    this.heading4TextStyle,
    this.heading5TextStyle,
    this.heading6TextStyle,
    this.linkTextStyle,
    this.inlineCodeTextStyle,
    this.inlineCodeBackgroundColor,
    this.codeBlockBackgroundColor,
    this.codeBlockHeaderBackgroundColor,
    this.codeBlockLanguageTextStyle,
    this.codeBlockTextStyle,
    this.quoteBackgroundColor,
    this.metadataBackgroundColor,
    this.metadataBorderColor,
    this.metadataTextStyle,
    this.tableBorderColor,
    this.tableHeaderBackgroundColor,
    this.thematicBreakColor,
    this.imageErrorBackgroundColor,
    this.imageErrorTextStyle,
    this.inlineLatexTextStyle,
    this.displayLatexTextStyle,
    this.latexErrorTextStyle,
    this.selectionColor,
  });

  /// Vertical spacing between top-level rendered blocks.
  final double blockSpacing;

  /// Text style for normal paragraphs.
  final TextStyle? paragraphTextStyle;

  /// Text style for level-1 headings.
  final TextStyle? heading1TextStyle;

  /// Text style for level-2 headings.
  final TextStyle? heading2TextStyle;

  /// Text style for level-3 headings.
  final TextStyle? heading3TextStyle;

  /// Text style for level-4 headings.
  final TextStyle? heading4TextStyle;

  /// Text style for level-5 headings.
  final TextStyle? heading5TextStyle;

  /// Text style for level-6 headings.
  final TextStyle? heading6TextStyle;

  /// Text style merged into inline link spans.
  final TextStyle? linkTextStyle;

  /// Text style for inline code spans.
  final TextStyle? inlineCodeTextStyle;

  /// Background color for inline code spans.
  final Color? inlineCodeBackgroundColor;

  /// Background color for fenced and indented code blocks.
  final Color? codeBlockBackgroundColor;

  /// Header background color for fenced code blocks with a language label.
  final Color? codeBlockHeaderBackgroundColor;

  /// Text style for code block language labels.
  final TextStyle? codeBlockLanguageTextStyle;

  /// Text style for code block contents.
  final TextStyle? codeBlockTextStyle;

  /// Background color for block quotes and callouts.
  final Color? quoteBackgroundColor;

  /// Background color for front matter and metadata blocks.
  final Color? metadataBackgroundColor;

  /// Border color for front matter and metadata blocks.
  final Color? metadataBorderColor;

  /// Text style for front matter and metadata blocks.
  final TextStyle? metadataTextStyle;

  /// Border color for rendered markdown tables.
  final Color? tableBorderColor;

  /// Background color for rendered markdown table headers.
  final Color? tableHeaderBackgroundColor;

  /// Color for thematic break dividers.
  final Color? thematicBreakColor;

  /// Background color used when an image fails to load.
  final Color? imageErrorBackgroundColor;

  /// Text style used when an image fails to load.
  final TextStyle? imageErrorTextStyle;

  /// Text style passed to inline KaTeX math expressions.
  final TextStyle? inlineLatexTextStyle;

  /// Text style passed to display KaTeX math expressions.
  final TextStyle? displayLatexTextStyle;

  /// Text style used when a LaTeX expression cannot be parsed.
  final TextStyle? latexErrorTextStyle;

  /// Selection highlight color used by selectable text.
  final Color? selectionColor;
}

/// Preferred theme type name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownThemeData = StreamingMarkdownThemeData;
