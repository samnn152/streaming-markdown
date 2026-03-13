import 'markdown_render_node.dart';
import 'rope_markdown_parser.dart';
import 'rope_string.dart';

/// Result returned by [StreamingMarkdownParseWorker.request].
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
  final Duration updateTime;
  final Duration statsTime;
  final Duration totalTime;
  final List<MarkdownRenderNode> visibleNodes;
  final List<MarkdownRenderNode> renderNodes;
}

/// Web/non-FFI fallback parse worker.
class StreamingMarkdownParseWorker {
  final RopeString _rope = RopeString();
  bool _started = false;

  Future<void> start() async {
    _started = true;
  }

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
