import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart'
    show
        LayerLink,
        LeaderLayer,
        PaintingContext,
        PipelineOwner,
        RenderObject,
        RenderEditable,
        RenderParagraph,
        RenderProxyBox,
        DirectionallyExtendSelectionEvent,
        GranularlyExtendSelectionEvent,
        SelectedContent,
        Selectable,
        SelectWordSelectionEvent,
        SelectionExtendDirection,
        SelectionEdgeUpdateEvent,
        SelectionEvent,
        SelectionEventType,
        SelectionGeometry,
        SelectionPoint,
        SelectionRegistrar,
        SelectionResult,
        SelectionStatus,
        SelectionUtils,
        TextGranularity;
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'dart:async';
import 'dart:collection';
import 'selection/web_copy_interceptor_stub.dart'
    if (dart.library.html) 'selection/web_copy_interceptor_web.dart'
    as web_copy;
import '../third_party/flutter_math/flutter_math.dart';

import '../copy/clipboard_handler.dart';
import '../copy/selection_strategy.dart';
import '../model/render_node.dart';
import '../model/inline_link.dart';
import '../worker/parse_worker_stub.dart'
    if (dart.library.ffi) '../worker/parse_worker.dart';

part 'api.dart';
part 'text/scaling.dart';
part 'text/blocks.dart';
part 'text/tables.dart';
part 'text/refs.dart';
part 'text/inline.dart';
part 'text/delims.dart';
part 'text/content.dart';
part 'text/models.dart';
part 'block/pipeline.dart';
part 'block/cache.dart';
part 'selection/projection.dart';
part 'selection/block_segments.dart';
part 'selection/tables.dart';
part 'selection/inline.dart';
part 'block/factory.dart';
part 'block/widgets.dart';
part 'block/tables.dart';
part 'block/metadata.dart';
part 'inline/spans.dart';
part 'inline/markdown.dart';
part 'inline/token_spans.dart';
part 'selection/area.dart';
part 'selection/controller.dart';
part 'selection/inline_proxy.dart';
part 'selection/model.dart';
part 'selection/pieces.dart';
part '../copy/plain_text_extractor.dart';
part '../copy/raw_markdown_extractor.dart';
part '../copy/html_converter.dart';
part 'animation/sequence.dart';
part 'animation/sequence_state.dart';
part 'animation/sequence_tokens.dart';
part 'animation/hosts.dart';
part 'animation/scheduled_reveal.dart';
part 'animation/token.dart';
part 'html/card.dart';
part 'html/renderer.dart';
part 'html/blocks.dart';
part 'html/inline.dart';

/// Animated markdown UI renderer for streaming chat-style text.
///
/// This is the primary widget API starting in `0.3.0`. It renders parsed
/// markdown [blocks] with stable block layout, token-level animation, optional
/// selection, and markdown-aware copy behavior.
///
/// When selection is enabled, selectable text is backed by render proxies that
/// resolve gestures to stable source ranges. Highlights are projected from
/// those ranges, so selection remains anchored while streams append or an
/// ancestor scrolls; table cells remain partially selectable and wide tables
/// can auto-scroll during a drag.
///
/// Use [StreamingMarkdownParseWorker.replace] or
/// [StreamingMarkdownParseWorker.append] to produce the [MarkdownRenderNode]
/// blocks passed here.
class AnimatedStreamingMarkdown extends StreamingMarkdownRenderView {
  /// Creates a markdown renderer from parsed [blocks].
  const AnimatedStreamingMarkdown({
    super.key,
    required List<MarkdownRenderNode> blocks,
    String placeholder = '',
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    bool asSliver = false,
    bool allowIncompleteInlineSyntax = false,
    Duration tokenStaggerDelay = Duration.zero,
    VoidCallback? onTokenDelay,
    VoidCallback? onTokenAnimationEnd,
    VoidCallback? onSequenceSettled,
    double tokenAnimationDurationFactor = 0,
    Duration? tokenAnimationDuration,
    Curve tokenAnimationCurve = Curves.easeOut,
    AnimatedMarkdownTokenBuilder? tokenAnimationBuilder,
    bool tokenAnimationPaused = false,
    AnimatedMarkdownTokenCompaction tokenCompaction =
        AnimatedMarkdownTokenCompaction.automatic,
    bool showTokenDebugColors = false,
    bool showCodeBlockCopyButton = false,
    bool enableSelection = false,
    SelectionStrategy selectionStrategy = SelectionStrategy.rich,
    AnimatedMarkdownSelectionController? selectionController,
    EdgeInsets selectionScrollPadding = const EdgeInsets.all(20),
    StreamingMarkdownThemeData theme = const StreamingMarkdownThemeData(),
    AnimatedMarkdownBlockBuilder? blockBuilder,
    AnimatedMarkdownImageBuilder? imageBuilder,
    AnimatedMarkdownLatexBuilder? latexBuilder,
    AnimatedMarkdownIncompleteLinkTextBuilder? incompleteLinkTextBuilder,
    PlaceholderAlignment inlineImageAlignment = PlaceholderAlignment.baseline,
    ValueChanged<String>? onLinkTap,
  }) : super(
          nodes: blocks,
          emptyPlaceholder: placeholder,
          padding: padding,
          sliver: asSliver,
          allowUnclosedInlineDelimiters: allowIncompleteInlineSyntax,
          tokenArrivalDelay: tokenStaggerDelay,
          onTokenArrivalWait: onTokenDelay,
          onTokenFadeInEnd: onTokenAnimationEnd,
          onSequenceSettled: onSequenceSettled,
          tokenFadeInRelativeToDelay: tokenAnimationDurationFactor,
          tokenFadeInDuration: tokenAnimationDuration,
          tokenFadeInCurve: tokenAnimationCurve,
          tokenAnimationBuilder: tokenAnimationBuilder,
          tokenAnimationPaused: tokenAnimationPaused,
          tokenCompaction: tokenCompaction,
          debugTokenHighlight: showTokenDebugColors,
          showCodeBlockCopyButton: showCodeBlockCopyButton,
          enableTextSelection: enableSelection,
          selectionStrategy: selectionStrategy,
          selectionController: selectionController,
          selectionScrollPadding: selectionScrollPadding,
          markdownTheme: theme,
          customBlockBuilder: blockBuilder,
          customImageBuilder: imageBuilder,
          customLatexBuilder: latexBuilder,
          incompleteLinkTextBuilder: incompleteLinkTextBuilder,
          inlineImageAlignment: inlineImageAlignment,
          onLinkTap: onLinkTap,
        );

  /// Creates a renderer by parsing a complete markdown string synchronously.
  ///
  /// This constructor is intended for short markdown where first-frame display
  /// matters more than moving parse work to the isolate-backed
  /// [MarkdownStreamParser]. For long or continuously streamed content, keep
  /// using [MarkdownStreamParser] and pass parsed [blocks] to the default
  /// constructor. The default [syncParserBackend] uses the pure-Dart parser to
  /// avoid native parser cold-start cost on the first frame.
  factory AnimatedStreamingMarkdown.fromMarkdown({
    Key? key,
    required String markdown,
    MarkdownSyncParserBackend syncParserBackend =
        MarkdownSyncParserBackend.dart,
    String placeholder = '',
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    bool asSliver = false,
    bool allowIncompleteInlineSyntax = false,
    Duration tokenStaggerDelay = Duration.zero,
    VoidCallback? onTokenDelay,
    VoidCallback? onTokenAnimationEnd,
    VoidCallback? onSequenceSettled,
    double tokenAnimationDurationFactor = 0,
    Duration? tokenAnimationDuration,
    Curve tokenAnimationCurve = Curves.easeOut,
    AnimatedMarkdownTokenBuilder? tokenAnimationBuilder,
    bool tokenAnimationPaused = false,
    AnimatedMarkdownTokenCompaction tokenCompaction =
        AnimatedMarkdownTokenCompaction.automatic,
    bool showTokenDebugColors = false,
    bool showCodeBlockCopyButton = false,
    bool enableSelection = false,
    SelectionStrategy selectionStrategy = SelectionStrategy.rich,
    AnimatedMarkdownSelectionController? selectionController,
    EdgeInsets selectionScrollPadding = const EdgeInsets.all(20),
    StreamingMarkdownThemeData theme = const StreamingMarkdownThemeData(),
    AnimatedMarkdownBlockBuilder? blockBuilder,
    AnimatedMarkdownImageBuilder? imageBuilder,
    AnimatedMarkdownLatexBuilder? latexBuilder,
    AnimatedMarkdownIncompleteLinkTextBuilder? incompleteLinkTextBuilder,
    PlaceholderAlignment inlineImageAlignment = PlaceholderAlignment.baseline,
    ValueChanged<String>? onLinkTap,
  }) {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      markdown,
      backend: syncParserBackend,
    );
    return AnimatedStreamingMarkdown(
      key: key,
      blocks: result.blocks,
      placeholder: placeholder,
      padding: padding,
      asSliver: asSliver,
      allowIncompleteInlineSyntax: allowIncompleteInlineSyntax,
      tokenStaggerDelay: tokenStaggerDelay,
      onTokenDelay: onTokenDelay,
      onTokenAnimationEnd: onTokenAnimationEnd,
      onSequenceSettled: onSequenceSettled,
      tokenAnimationDurationFactor: tokenAnimationDurationFactor,
      tokenAnimationDuration: tokenAnimationDuration,
      tokenAnimationCurve: tokenAnimationCurve,
      tokenAnimationBuilder: tokenAnimationBuilder,
      tokenAnimationPaused: tokenAnimationPaused,
      tokenCompaction: tokenCompaction,
      showTokenDebugColors: showTokenDebugColors,
      showCodeBlockCopyButton: showCodeBlockCopyButton,
      enableSelection: enableSelection,
      selectionStrategy: selectionStrategy,
      selectionController: selectionController,
      selectionScrollPadding: selectionScrollPadding,
      theme: theme,
      blockBuilder: blockBuilder,
      imageBuilder: imageBuilder,
      latexBuilder: latexBuilder,
      incompleteLinkTextBuilder: incompleteLinkTextBuilder,
      inlineImageAlignment: inlineImageAlignment,
      onLinkTap: onLinkTap,
    );
  }
}

/// Legacy name for [AnimatedStreamingMarkdown].
///
/// New code should use [AnimatedStreamingMarkdown], whose constructor names
/// describe the current behavior more directly. This class remains available
/// for `0.2.x` compatibility.
///
/// Streaming markdown UI renderer.
///
/// Input is a list of [MarkdownRenderNode] blocks (typically produced by
/// [StreamingMarkdownParseWorker]). This widget focuses on real-time streaming
/// behavior: partial markdown tolerance, token-level fade-in, and optional text
/// selection support.
class StreamingMarkdownRenderView extends StatelessWidget {
  static final Map<String, _ParsedTable> _tableSnapshotCache =
      <String, _ParsedTable>{};
  static const int _tableSnapshotCacheLimit = 256;

  const StreamingMarkdownRenderView({
    super.key,
    required this.nodes,
    this.emptyPlaceholder = '',
    this.padding = const EdgeInsets.all(12),
    this.sliver = false,
    this.allowUnclosedInlineDelimiters = false,
    this.tokenArrivalDelay = Duration.zero,
    this.onTokenArrivalWait,
    this.onTokenFadeInEnd,
    this.onSequenceSettled,
    this.tokenFadeInRelativeToDelay = 0,
    this.tokenFadeInDuration,
    this.tokenFadeInCurve = Curves.easeOut,
    this.tokenAnimationBuilder,
    this.tokenAnimationPaused = false,
    this.tokenCompaction = AnimatedMarkdownTokenCompaction.automatic,
    this.debugTokenHighlight = false,
    this.showCodeBlockCopyButton = false,
    this.enableTextSelection = false,
    this.selectionStrategy = SelectionStrategy.rich,
    this.selectionController,
    this.selectionScrollPadding = const EdgeInsets.all(20),
    this.markdownTheme = const StreamingMarkdownThemeData(),
    this.customBlockBuilder,
    this.customImageBuilder,
    this.customLatexBuilder,
    this.incompleteLinkTextBuilder,
    this.inlineImageAlignment = PlaceholderAlignment.baseline,
    this.onLinkTap,
  });

  /// Render nodes to display.
  final List<MarkdownRenderNode> nodes;

  /// Placeholder text shown when [nodes] contains no renderable blocks.
  final String emptyPlaceholder;

  /// Outer padding around rendered content.
  final EdgeInsetsGeometry padding;

  /// Whether this widget should return a sliver instead of a box widget.
  final bool sliver;

  /// Allows unfinished inline emphasis/link delimiters to render during
  /// streaming instead of waiting for the closing delimiter.
  final bool allowUnclosedInlineDelimiters;

  /// Delay between adjacent token reveal starts.
  final Duration tokenArrivalDelay;

  /// Called when the renderer is waiting for a delayed token reveal.
  final VoidCallback? onTokenArrivalWait;

  /// Called when a token fade animation completes.
  final VoidCallback? onTokenFadeInEnd;

  /// Called when all markdown blocks have become visible in sequence.
  final VoidCallback? onSequenceSettled;

  /// Computes fade duration as a multiple of [tokenArrivalDelay] when
  /// [tokenFadeInDuration] is not provided.
  final double tokenFadeInRelativeToDelay;

  /// Absolute fade duration for each token.
  final Duration? tokenFadeInDuration;

  /// Curve applied to each token fade animation.
  final Curve tokenFadeInCurve;

  /// Optional custom token animation builder.
  final StreamingMarkdownTokenAnimationBuilder? tokenAnimationBuilder;

  /// Pauses token and block reveal scheduling without changing parser input.
  final bool tokenAnimationPaused;

  /// Merges settled animated word tokens back into static text spans without
  /// changing their measured geometry or interrupting reveal animations.
  final AnimatedMarkdownTokenCompaction tokenCompaction;

  /// Paints token debug backgrounds to inspect token boundaries.
  final bool debugTokenHighlight;

  /// Shows a copy button in fenced and indented code block headers.
  final bool showCodeBlockCopyButton;

  /// Enables render-backed selectable text and markdown-aware copy behavior.
  ///
  /// Selection stores stable source offsets rather than inferring a range from
  /// overlaid visual text, preserving anchors during scrolling and streaming.
  /// Dragging near a scroll edge automatically extends selection through the
  /// scrollable viewport, including horizontal Markdown tables.
  final bool enableTextSelection;

  /// Controls whether copied selections become plain text, raw markdown,
  /// or rich HTML with a plain-text fallback.
  final SelectionStrategy selectionStrategy;

  /// Optional source-backed selection controller.
  ///
  /// Box mode owns an internal controller when this is null. Sliver mode uses
  /// the controller supplied by [AnimatedStreamingMarkdownSelectionArea].
  final AnimatedMarkdownSelectionController? selectionController;

  /// Padding maintained around a programmatically revealed selection endpoint.
  final EdgeInsets selectionScrollPadding;

  /// Theme data for markdown block styling.
  final StreamingMarkdownThemeData markdownTheme;

  /// Optional block override hook.
  final StreamingMarkdownBlockBuilder? customBlockBuilder;

  /// Optional image override hook.
  final StreamingMarkdownImageBuilder? customImageBuilder;

  /// Optional LaTeX/math override hook.
  final StreamingMarkdownLatexBuilder? customLatexBuilder;

  /// Optional presentation policy for a semantic incomplete inline link.
  ///
  /// When omitted, no text is shown until a destination starts arriving; the
  /// current destination is then shown until completion. A completed link
  /// always follows the normal linked-label rendering path.
  final StreamingMarkdownIncompleteLinkTextBuilder? incompleteLinkTextBuilder;

  /// Alignment used for inline markdown image widget spans.
  final PlaceholderAlignment inlineImageAlignment;

  /// Link tap callback. Defaults to no-op when omitted.
  final ValueChanged<String>? onLinkTap;

  Duration _resolvedTokenFadeInDuration() {
    final Duration? absolute = tokenFadeInDuration;
    if (absolute != null) {
      return absolute <= Duration.zero ? Duration.zero : absolute;
    }
    if (tokenFadeInRelativeToDelay <= 0 || tokenArrivalDelay <= Duration.zero) {
      return Duration.zero;
    }
    final int micros =
        (tokenArrivalDelay.inMicroseconds * tokenFadeInRelativeToDelay).round();
    if (micros <= 0) {
      return Duration.zero;
    }
    return Duration(microseconds: micros);
  }

  @visibleForTesting
  static String debugMarkdownForSelectedPlainText({
    required List<MarkdownRenderNode> nodes,
    required String selectedPlainText,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
      nodes: nodes,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<MarkdownRenderNode> blocks =
        view._collectRenderableBlocks(nodes);
    final Map<String, String> linkReferences =
        view._extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers =
        view._extractFootnoteNumbers(nodes);
    final _MarkdownSelectionProjection projection =
        view._buildSelectionProjection(
      blocks,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    return projection.markdownForSelectedPlainText(selectedPlainText);
  }

  @visibleForTesting
  static String debugPlainTextForSelectedPlainText({
    required List<MarkdownRenderNode> nodes,
    required String selectedPlainText,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
      nodes: nodes,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<MarkdownRenderNode> blocks =
        view._collectRenderableBlocks(nodes);
    final Map<String, String> linkReferences =
        view._extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers =
        view._extractFootnoteNumbers(nodes);
    final _MarkdownSelectionProjection projection =
        view._buildSelectionProjection(
      blocks,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    return projection.plainTextForSelectedPlainText(selectedPlainText);
  }

  @visibleForTesting
  static String debugFullPlainText({
    required List<MarkdownRenderNode> nodes,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
      nodes: nodes,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<MarkdownRenderNode> blocks =
        view._collectRenderableBlocks(nodes);
    final Map<String, String> linkReferences =
        view._extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers =
        view._extractFootnoteNumbers(nodes);
    final _MarkdownSelectionProjection projection =
        view._buildSelectionProjection(
      blocks,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    return projection.segments
        .where(
          (_MarkdownSelectionSegment segment) =>
              segment.plainText.isNotEmpty || segment.markdownText.isNotEmpty,
        )
        .map((_MarkdownSelectionSegment segment) => segment.plainText)
        .join('\n\n');
  }

  @visibleForTesting
  static String debugHtmlForSelectedPlainText({
    required List<MarkdownRenderNode> nodes,
    required String selectedPlainText,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final String markdown = debugMarkdownForSelectedPlainText(
      nodes: nodes,
      selectedPlainText: selectedPlainText,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    if (markdown.isEmpty) {
      return '';
    }
    return _selectedMarkdownToHtml(
      markdown,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
  }

  @visibleForTesting
  static String debugMarkdownForSelectionRange({
    required List<MarkdownRenderNode> nodes,
    required int selectionStart,
    required int selectionEnd,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
      nodes: nodes,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<MarkdownRenderNode> blocks =
        view._collectRenderableBlocks(nodes);
    final Map<String, String> linkReferences =
        view._extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers =
        view._extractFootnoteNumbers(nodes);
    final _MarkdownSelectionProjection projection =
        view._buildSelectionProjection(
      blocks,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    return projection.markdownForRange(
      _MarkdownSelectionRange(start: selectionStart, end: selectionEnd),
    );
  }

  @visibleForTesting
  static (int, int)? debugMarkdownSourceRangeForSelectedPlainText({
    required List<MarkdownRenderNode> nodes,
    required String selectedPlainText,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
      nodes: nodes,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<MarkdownRenderNode> blocks =
        view._collectRenderableBlocks(nodes);
    final Map<String, String> linkReferences =
        view._extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers =
        view._extractFootnoteNumbers(nodes);
    final _MarkdownSelectionProjection projection =
        view._buildSelectionProjection(
      blocks,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    final _MarkdownSourceSelectionRange? range =
        projection.sourceRangeForSelectedPlainText(selectedPlainText);
    if (range == null) {
      return null;
    }
    return (range.start, range.end);
  }

  @visibleForTesting
  static String debugMarkdownForSourceRange({
    required List<MarkdownRenderNode> nodes,
    required int sourceStart,
    required int sourceEnd,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
      nodes: nodes,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<MarkdownRenderNode> blocks =
        view._collectRenderableBlocks(nodes);
    final Map<String, String> linkReferences =
        view._extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers =
        view._extractFootnoteNumbers(nodes);
    final _MarkdownSelectionProjection projection =
        view._buildSelectionProjection(
      blocks,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    return projection.markdownForSourceRange(
      _MarkdownSourceSelectionRange(start: sourceStart, end: sourceEnd),
    );
  }

  @visibleForTesting
  static String debugFullHtml({
    required List<MarkdownRenderNode> nodes,
    bool allowUnclosedInlineDelimiters = false,
  }) {
    final StreamingMarkdownRenderView view = StreamingMarkdownRenderView(
      nodes: nodes,
      allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
    );
    final List<MarkdownRenderNode> blocks =
        view._collectRenderableBlocks(nodes);
    final Map<String, String> linkReferences =
        view._extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers =
        view._extractFootnoteNumbers(nodes);
    final _MarkdownHtmlSelectionConverter converter =
        _MarkdownHtmlSelectionConverter(
      view: view,
      blocks: blocks,
      linkReferences: linkReferences,
      footnoteNumbers: footnoteNumbers,
    );
    return converter.convert();
  }

  @override
  Widget build(BuildContext context) {
    final List<MarkdownRenderNode> blocks = _collectRenderableBlocks(nodes);
    final _MarkdownSelectionHost? sliverSelectionHost =
        enableTextSelection && sliver
            ? _MarkdownSelectionHostScope.maybeOf(context)
            : null;
    assert(
      !enableTextSelection || !sliver || sliverSelectionHost != null,
      'Selectable sliver Markdown must be inside an '
      'AnimatedStreamingMarkdownSelectionArea.',
    );
    final bool selectionEnabled =
        enableTextSelection && (!sliver || sliverSelectionHost != null);
    if (blocks.isEmpty) {
      final Widget empty = Center(
        child: Text(emptyPlaceholder, textAlign: TextAlign.center),
      );
      final Widget emptyContent = !sliver
          ? empty
          : SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(padding: padding, child: empty),
            );
      if (!selectionEnabled) {
        return emptyContent;
      }
      final _MarkdownSelectionDocument emptyDocument =
          _MarkdownSelectionDocument(
        projection: const _MarkdownSelectionProjection(
          <_MarkdownSelectionSegment>[],
        ),
        blockRanges: const <String, _MarkdownSelectionBlockRange>{},
        selectionStrategy: selectionStrategy,
        allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
        selectionColor: markdownTheme.selectionColor ?? const Color(0x6658A6FF),
      );
      if (sliver) {
        return _MarkdownSelectionDocumentRegistration(
          host: sliverSelectionHost!,
          document: emptyDocument,
          rendererController: selectionController,
          child: emptyContent,
        );
      }
      return _MarkdownSelectionArea(
        document: emptyDocument,
        selectionController: selectionController,
        scrollPadding: selectionScrollPadding,
        child: emptyContent,
      );
    }

    final Map<String, String> linkReferences = _extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers = _extractFootnoteNumbers(nodes);
    final String refsDigest = _linkReferencesDigest(linkReferences);
    final String renderConfigDigest = _renderConfigDigest(context);
    final bool compactSettledTokens = _shouldCompactSettledTokens();
    final _MarkdownSelectionProjection? selectionProjection = selectionEnabled
        ? _buildSelectionProjection(
            blocks,
            linkReferences: linkReferences,
            footnoteNumbers: footnoteNumbers,
          )
        : null;
    final Map<String, _MarkdownSelectionBlockRange> blockRanges =
        selectionProjection == null
            ? const <String, _MarkdownSelectionBlockRange>{}
            : _buildSelectionBlockRanges(blocks, selectionProjection);
    final _MarkdownSelectionDocument? selectionDocument =
        selectionProjection == null
            ? null
            : _MarkdownSelectionDocument(
                projection: selectionProjection,
                blockRanges: blockRanges,
                selectionStrategy: selectionStrategy,
                allowUnclosedInlineDelimiters: allowUnclosedInlineDelimiters,
                selectionColor:
                    markdownTheme.selectionColor ?? const Color(0x6658A6FF),
              );

    final Widget content = _SequencedBlockList(
      blocks: blocks,
      sliver: sliver,
      padding: padding,
      blockSpacing: markdownTheme.blockSpacing,
      tokenArrivalDelay: tokenArrivalDelay,
      paused: tokenAnimationPaused,
      onWait: onTokenArrivalWait,
      onSequenceSettled: onSequenceSettled,
      blockIdentityBuilder: _blockIdentity,
      blockBuilder: (BuildContext context, MarkdownRenderNode block) {
        Widget renderedBlock = _BlockRenderHost(
          key: ValueKey<String>(_blockIdentity(block)),
          signature: _blockSignature(
            block,
            refsDigest,
            renderConfigDigest,
          ),
          selectionIdentity: _blockIdentity(block),
          node: block,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
          compactSettledTokens: compactSettledTokens,
          compactionDelay: _tokenCompactionDelay(block),
          builder: _buildRenderedBlockWithRefs,
        );
        final _MarkdownSelectionBlockRange? blockRange =
            blockRanges[_blockIdentity(block)];
        if (blockRange != null) {
          renderedBlock = _MarkdownSelectionBlockVisualScope(
            blockRange: blockRange,
            child: renderedBlock,
          );
        }
        return renderedBlock;
      },
    );

    if (!selectionEnabled) {
      return content;
    }
    if (sliver) {
      return _MarkdownSelectionDocumentRegistration(
        host: sliverSelectionHost!,
        document: selectionDocument!,
        rendererController: selectionController,
        child: content,
      );
    }
    return _MarkdownSelectionArea(
      document: selectionDocument!,
      selectionController: selectionController,
      scrollPadding: selectionScrollPadding,
      child: content,
    );
  }

  Map<String, _MarkdownSelectionBlockRange> _buildSelectionBlockRanges(
    List<MarkdownRenderNode> blocks,
    _MarkdownSelectionProjection projection,
  ) {
    final Map<String, _MarkdownSelectionBlockRange> ranges =
        <String, _MarkdownSelectionBlockRange>{};
    int sourceCursor = 0;
    int plainCursor = 0;
    int compactCursor = 0;
    for (int i = 0; i < blocks.length && i < projection.segments.length; i++) {
      if (i > 0) {
        sourceCursor += 2;
        plainCursor += 2;
      }
      final _MarkdownSelectionSegment segment = projection.segments[i];
      final int sourceStart = sourceCursor;
      final int sourceEnd = sourceStart + segment.markdownText.length;
      final int plainStart = plainCursor;
      final int plainEnd = plainStart + segment.plainText.length;
      final int compactStart = compactCursor;
      final int compactEnd = compactStart + segment.plainText.length;
      ranges[_blockIdentity(blocks[i])] = _MarkdownSelectionBlockRange(
        sourceRange: _MarkdownSourceSelectionRange(
          start: sourceStart,
          end: sourceEnd,
        ),
        plainRange: _MarkdownSelectionRange(
          start: plainStart,
          end: plainEnd,
        ),
        compactRange: _MarkdownSelectionRange(
          start: compactStart,
          end: compactEnd,
        ),
      );
      sourceCursor = sourceEnd;
      plainCursor = plainEnd;
      compactCursor = compactEnd;
    }
    return ranges;
  }

  bool _shouldCompactSettledTokens() {
    if (tokenCompaction == AnimatedMarkdownTokenCompaction.disabled) {
      return false;
    }
    if (tokenCompaction == AnimatedMarkdownTokenCompaction.automatic &&
        debugTokenHighlight) {
      return false;
    }
    return true;
  }

  Duration _tokenCompactionDelay(MarkdownRenderNode node) {
    final int tokens = _roughAnimatedTokenCountForNode(node);
    final Duration fade = _resolvedTokenFadeInDuration();
    if (tokens <= 1 || tokenArrivalDelay <= Duration.zero) {
      return fade;
    }
    return tokenArrivalDelay * (tokens - 1) + fade;
  }

  int _roughAnimatedTokenCountForNode(MarkdownRenderNode node) {
    if (node.type == 'thematic_break' ||
        node.type == 'pipe_table_delimiter_row') {
      return 0;
    }
    final String text =
        (node.content.isNotEmpty ? node.content : node.raw).trim();
    if (text.isEmpty) {
      return 1;
    }
    final int count = RegExp(r'\S+').allMatches(text).length;
    return count <= 0 ? 1 : count;
  }
}
