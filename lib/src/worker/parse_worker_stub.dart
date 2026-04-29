import '../model/render_node.dart';
import '../parser/rope_markdown_parser.dart';
import '../model/rope.dart';

/// Preferred result type name for parser operations.
typedef MarkdownParseResult = StreamingMarkdownParseResult;

/// Operation type for [StreamingMarkdownParseWorker.parse].
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

  final int basicBlockCount;
  final int inlineTypeCount;
  final bool nativeAvailable;
  final String mode;
  final bool nodesIncluded;
  bool get includesNodes => nodesIncluded;
  final Duration updateTime;
  final Duration statsTime;
  final Duration totalTime;
  final List<MarkdownRenderNode> visibleNodes;
  final List<MarkdownRenderNode> renderNodes;
  List<MarkdownRenderNode> get blocks => renderNodes;
}

/// Web/non-FFI fallback parse worker.
class StreamingMarkdownParseWorker {
  final RopeString _rope = RopeString();
  bool _started = false;

  Future<void> start() async {
    _started = true;
  }

  Future<StreamingMarkdownParseResult> parse({
    required MarkdownParseOperation operation,
    required String text,
    bool includeNodes = true,
  }) {
    return request(
      op: operation.wireName,
      text: text,
      includeNodes: includeNodes,
    );
  }

  Future<StreamingMarkdownParseResult> replace(
    String markdown, {
    bool includeNodes = true,
  }) {
    return parse(
      operation: MarkdownParseOperation.replace,
      text: markdown,
      includeNodes: includeNodes,
    );
  }

  Future<StreamingMarkdownParseResult> append(
    String chunk, {
    bool includeNodes = true,
  }) {
    return parse(
      operation: MarkdownParseOperation.append,
      text: chunk,
      includeNodes: includeNodes,
    );
  }

  /// Prefer [parse], [replace], or [append] in new code.
  Future<StreamingMarkdownParseResult> request({
    required String op,
    required String text,
    required bool includeNodes,
  }) async {
    if (!_started) {
      throw StateError('Parse worker is not started');
    }

    final Stopwatch totalWatch = Stopwatch()..start();
    final Stopwatch updateWatch = Stopwatch()..start();
    if (op == 'append') {
      _rope.append(text);
    } else {
      _rope
        ..clear()
        ..append(text);
    }
    updateWatch.stop();

    final Stopwatch statsWatch = Stopwatch()..start();
    final int blockCount =
        const RopeMarkdownParser().parse(_rope).blocks.length;
    statsWatch.stop();
    totalWatch.stop();

    return StreamingMarkdownParseResult(
      basicBlockCount: blockCount,
      inlineTypeCount: 0,
      nativeAvailable: false,
      mode: op == 'append' ? 'fallback-append' : 'fallback-set',
      nodesIncluded: includeNodes,
      updateTime: updateWatch.elapsed,
      statsTime: statsWatch.elapsed,
      totalTime: totalWatch.elapsed,
      visibleNodes: const <MarkdownRenderNode>[],
      renderNodes: const <MarkdownRenderNode>[],
    );
  }

  void dispose() {
    _rope.clear();
    _started = false;
  }
}

/// Preferred parser name for streamed markdown sources.
class MarkdownStreamParser extends StreamingMarkdownParseWorker {}
