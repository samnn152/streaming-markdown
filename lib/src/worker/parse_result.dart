part of 'parse_worker.dart';

/// Preferred result type name for parser operations.
typedef MarkdownParseResult = StreamingMarkdownParseResult;

/// Operation type for [StreamingMarkdownParseWorker.parse].
///
/// Use [replace] when the incoming text is a full document snapshot and
/// [append] when the incoming text is only the next streamed chunk.
enum MarkdownParseOperation {
  /// Replace the current parser buffer with a complete markdown document.
  replace,

  /// Append a markdown chunk to the current parser buffer.
  append,
}

extension _MarkdownParseOperationWire on MarkdownParseOperation {
  String get wireName {
    switch (this) {
      case MarkdownParseOperation.append:
        return 'append';
      case MarkdownParseOperation.replace:
        return 'set';
    }
  }
}

/// Result returned by [StreamingMarkdownParseWorker.parse].
class StreamingMarkdownParseResult {
  const StreamingMarkdownParseResult({
    required this.basicBlockCount,
    required this.inlineTypeCount,
    required this.nativeAvailable,
    required this.mode,
    required this.nodesIncluded,
    required this.updateTime,
    required this.statsTime,
    required this.totalTime,
    required this.visibleNodes,
    required this.renderNodes,
  });

  /// Number of block nodes reported by the parser.
  final int basicBlockCount;

  /// Number of inline node types observed.
  final int inlineTypeCount;

  /// Whether native library parsing was available for this request.
  final bool nativeAvailable;

  /// Parse mode string (for diagnostics only).
  final String mode;

  /// Whether node payloads were included.
  final bool nodesIncluded;

  /// Whether node payloads were included.
  ///
  /// Prefer this name in new code. [nodesIncluded] remains available for
  /// compatibility with `0.2.x`.
  bool get includesNodes => nodesIncluded;

  /// Time spent updating parser state.
  final Duration updateTime;

  /// Time spent generating result statistics and node payloads.
  final Duration statsTime;

  /// End-to-end request time.
  final Duration totalTime;

  /// Visible normalized nodes.
  final List<MarkdownRenderNode> visibleNodes;

  /// Nodes intended for UI rendering.
  final List<MarkdownRenderNode> renderNodes;

  /// Markdown blocks ready for [AnimatedStreamingMarkdown].
  ///
  /// Prefer this name in new code. [renderNodes] remains available for
  /// compatibility with `0.2.x`.
  List<MarkdownRenderNode> get blocks => renderNodes;
}
