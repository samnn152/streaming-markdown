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

/// Preferred token animation builder name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownTokenBuilder = StreamingMarkdownTokenAnimationBuilder;

/// Preferred block override builder name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownBlockBuilder = StreamingMarkdownBlockBuilder;

/// Preferred public name for block override context.
typedef AnimatedMarkdownBlockContext = StreamingMarkdownBlockBuildContext;

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

  /// Selection highlight color used by selectable inline overlays.
  final Color? selectionColor;
}

/// Preferred theme type name for [AnimatedStreamingMarkdown].
typedef AnimatedMarkdownThemeData = StreamingMarkdownThemeData;
