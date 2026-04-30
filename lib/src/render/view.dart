import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'dart:async';
import 'dart:collection';

import '../model/render_node.dart';
import '../worker/parse_worker_stub.dart'
    if (dart.library.ffi) '../worker/parse_worker.dart';

part 'api.dart';
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
part 'selection/model.dart';
part 'selection/pieces.dart';
part 'selection/overlay.dart';
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
    double tokenAnimationDurationFactor = 0,
    Duration? tokenAnimationDuration,
    Curve tokenAnimationCurve = Curves.easeOut,
    AnimatedMarkdownTokenBuilder? tokenAnimationBuilder,
    bool tokenAnimationPaused = false,
    AnimatedMarkdownTokenCompaction tokenCompaction =
        AnimatedMarkdownTokenCompaction.automatic,
    bool showTokenDebugColors = false,
    bool enableSelection = false,
    StreamingMarkdownThemeData theme = const StreamingMarkdownThemeData(),
    AnimatedMarkdownBlockBuilder? blockBuilder,
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
          tokenFadeInRelativeToDelay: tokenAnimationDurationFactor,
          tokenFadeInDuration: tokenAnimationDuration,
          tokenFadeInCurve: tokenAnimationCurve,
          tokenAnimationBuilder: tokenAnimationBuilder,
          tokenAnimationPaused: tokenAnimationPaused,
          tokenCompaction: tokenCompaction,
          debugTokenHighlight: showTokenDebugColors,
          enableTextSelection: enableSelection,
          markdownTheme: theme,
          customBlockBuilder: blockBuilder,
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
    double tokenAnimationDurationFactor = 0,
    Duration? tokenAnimationDuration,
    Curve tokenAnimationCurve = Curves.easeOut,
    AnimatedMarkdownTokenBuilder? tokenAnimationBuilder,
    bool tokenAnimationPaused = false,
    AnimatedMarkdownTokenCompaction tokenCompaction =
        AnimatedMarkdownTokenCompaction.automatic,
    bool showTokenDebugColors = false,
    bool enableSelection = false,
    StreamingMarkdownThemeData theme = const StreamingMarkdownThemeData(),
    AnimatedMarkdownBlockBuilder? blockBuilder,
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
      tokenAnimationDurationFactor: tokenAnimationDurationFactor,
      tokenAnimationDuration: tokenAnimationDuration,
      tokenAnimationCurve: tokenAnimationCurve,
      tokenAnimationBuilder: tokenAnimationBuilder,
      tokenAnimationPaused: tokenAnimationPaused,
      tokenCompaction: tokenCompaction,
      showTokenDebugColors: showTokenDebugColors,
      enableSelection: enableSelection,
      theme: theme,
      blockBuilder: blockBuilder,
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
    this.tokenFadeInRelativeToDelay = 0,
    this.tokenFadeInDuration,
    this.tokenFadeInCurve = Curves.easeOut,
    this.tokenAnimationBuilder,
    this.tokenAnimationPaused = false,
    this.tokenCompaction = AnimatedMarkdownTokenCompaction.automatic,
    this.debugTokenHighlight = false,
    this.enableTextSelection = false,
    this.markdownTheme = const StreamingMarkdownThemeData(),
    this.customBlockBuilder,
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

  /// Merges settled animated word tokens back into static text spans.
  final AnimatedMarkdownTokenCompaction tokenCompaction;

  /// Paints token debug backgrounds to inspect token boundaries.
  final bool debugTokenHighlight;

  /// Enables selectable text and markdown-aware copy behavior.
  final bool enableTextSelection;

  /// Theme data for markdown block styling.
  final StreamingMarkdownThemeData markdownTheme;

  /// Optional block override hook.
  final StreamingMarkdownBlockBuilder? customBlockBuilder;

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

  @override
  Widget build(BuildContext context) {
    final List<MarkdownRenderNode> blocks = _collectRenderableBlocks(nodes);
    if (blocks.isEmpty) {
      final Widget empty = Center(
        child: Text(emptyPlaceholder, textAlign: TextAlign.center),
      );
      if (!sliver) {
        return empty;
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(padding: padding, child: empty),
      );
    }

    final Map<String, String> linkReferences = _extractLinkReferences(nodes);
    final Map<String, int> footnoteNumbers = _extractFootnoteNumbers(nodes);
    final String refsDigest = _linkReferencesDigest(linkReferences);
    final String renderConfigDigest = _renderConfigDigest(context);
    final bool compactSettledTokens = _shouldCompactSettledTokens();

    final Widget content = _SequencedBlockList(
      blocks: blocks,
      sliver: sliver,
      padding: padding,
      blockSpacing: markdownTheme.blockSpacing,
      tokenArrivalDelay: tokenArrivalDelay,
      paused: tokenAnimationPaused,
      onWait: onTokenArrivalWait,
      blockIdentityBuilder: _blockIdentity,
      blockBuilder: (BuildContext context, MarkdownRenderNode block) {
        return _BlockRenderHost(
          key: ValueKey<String>(_blockIdentity(block)),
          signature: _blockSignature(
            block,
            refsDigest,
            renderConfigDigest,
          ),
          node: block,
          linkReferences: linkReferences,
          footnoteNumbers: footnoteNumbers,
          compactSettledTokens: compactSettledTokens,
          compactionDelay: _tokenCompactionDelay(block),
          builder: _buildRenderedBlockWithRefs,
        );
      },
    );

    if (!enableTextSelection || sliver) {
      return content;
    }
    return _MarkdownSelectionArea(
      projection: _buildSelectionProjection(
        blocks,
        linkReferences: linkReferences,
        footnoteNumbers: footnoteNumbers,
      ),
      child: content,
    );
  }

  bool _shouldCompactSettledTokens() {
    if (tokenCompaction == AnimatedMarkdownTokenCompaction.disabled) {
      return false;
    }
    if (tokenCompaction == AnimatedMarkdownTokenCompaction.automatic &&
        (debugTokenHighlight || tokenAnimationBuilder != null)) {
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
