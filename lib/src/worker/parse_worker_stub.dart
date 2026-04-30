import '../model/block_nodes.dart';
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

/// Result returned by [warmUpStreamingMarkdownParser].
class StreamingMarkdownWarmUpResult {
  const StreamingMarkdownWarmUpResult({
    required this.nativeAvailable,
    required this.currentIsolateTime,
    required this.workerTime,
    required this.totalTime,
  });

  /// Whether the native parser was available during warm-up.
  final bool nativeAvailable;

  /// Time spent warming parser resources on the current isolate.
  final Duration currentIsolateTime;

  /// Time spent warming an isolate-backed [StreamingMarkdownParseWorker].
  final Duration? workerTime;

  /// End-to-end warm-up time.
  final Duration totalTime;
}

/// Warms parser resources before the first visible markdown render.
///
/// Non-FFI builds do not have a native parser to load, so this warms the
/// pure-Dart parser path and optionally the fallback worker wrapper.
Future<StreamingMarkdownWarmUpResult> warmUpStreamingMarkdownParser({
  bool includeWorker = false,
}) async {
  final Stopwatch totalWatch = Stopwatch()..start();
  final Stopwatch currentWatch = Stopwatch()..start();
  MarkdownSyncParser.parseMarkdown('', includeNodes: false);
  currentWatch.stop();

  Duration? workerTime;
  if (includeWorker) {
    final Stopwatch workerWatch = Stopwatch()..start();
    final StreamingMarkdownParseWorker worker = StreamingMarkdownParseWorker();
    await worker.start();
    try {
      await worker.replace('', includeNodes: false);
    } finally {
      worker.dispose();
      workerWatch.stop();
    }
    workerTime = workerWatch.elapsed;
  }

  totalWatch.stop();
  return StreamingMarkdownWarmUpResult(
    nativeAvailable: false,
    currentIsolateTime: currentWatch.elapsed,
    workerTime: workerTime,
    totalTime: totalWatch.elapsed,
  );
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

/// Parser backend used by [MarkdownSyncParser].
enum MarkdownSyncParserBackend {
  /// Use the native parser when available, otherwise fall back to pure Dart.
  auto,

  /// Force the native parser. Non-FFI builds fall back to pure Dart.
  native,

  /// Force the pure-Dart rope parser.
  dart,
}

/// Synchronous markdown parser for short documents and first-frame rendering.
///
/// This non-FFI implementation uses the pure-Dart rope parser on the current
/// isolate. Prefer [StreamingMarkdownParseWorker] for long streamed content.
class MarkdownSyncParser {
  /// Creates a parser session.
  MarkdownSyncParser({
    MarkdownSyncParserBackend backend = MarkdownSyncParserBackend.auto,
  }) : _backend = backend;

  final MarkdownSyncParserBackend _backend;
  final RopeString _rope = RopeString();

  /// Parses a complete markdown string without keeping parser state.
  static StreamingMarkdownParseResult parseMarkdown(
    String markdown, {
    bool includeNodes = true,
    MarkdownSyncParserBackend backend = MarkdownSyncParserBackend.auto,
  }) {
    final MarkdownSyncParser parser = MarkdownSyncParser(backend: backend);
    try {
      return parser.replace(markdown, includeNodes: includeNodes);
    } finally {
      parser.dispose();
    }
  }

  /// Parses [text] using a typed [operation].
  StreamingMarkdownParseResult parse({
    required MarkdownParseOperation operation,
    required String text,
    bool includeNodes = true,
  }) {
    return _requestSync(
      op: operation.wireName,
      text: text,
      includeNodes: includeNodes,
    );
  }

  /// Replaces the current parser buffer with [markdown].
  StreamingMarkdownParseResult replace(
    String markdown, {
    bool includeNodes = true,
  }) {
    return parse(
      operation: MarkdownParseOperation.replace,
      text: markdown,
      includeNodes: includeNodes,
    );
  }

  /// Appends [chunk] to the current parser buffer.
  StreamingMarkdownParseResult append(
    String chunk, {
    bool includeNodes = true,
  }) {
    return parse(
      operation: MarkdownParseOperation.append,
      text: chunk,
      includeNodes: includeNodes,
    );
  }

  StreamingMarkdownParseResult _requestSync({
    required String op,
    required String text,
    required bool includeNodes,
  }) {
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
    final MarkdownDocument document = const RopeMarkdownParser().parse(_rope);
    final List<MarkdownRenderNode> renderNodes = includeNodes
        ? _renderNodesFromDocument(document, _rope.toString())
        : const <MarkdownRenderNode>[];
    statsWatch.stop();
    totalWatch.stop();

    return StreamingMarkdownParseResult(
      basicBlockCount: document.blocks.length,
      inlineTypeCount: 0,
      nativeAvailable: false,
      mode: op == 'append' ? _appendMode : _setMode,
      nodesIncluded: includeNodes,
      updateTime: updateWatch.elapsed,
      statsTime: statsWatch.elapsed,
      totalTime: totalWatch.elapsed,
      visibleNodes: renderNodes,
      renderNodes: renderNodes,
    );
  }

  String get _appendMode {
    return _backend == MarkdownSyncParserBackend.dart
        ? 'sync-dart-append'
        : 'sync-fallback-append';
  }

  String get _setMode {
    return _backend == MarkdownSyncParserBackend.dart
        ? 'sync-dart-set'
        : 'sync-fallback-set';
  }

  /// Clears parser state.
  void dispose() {
    _rope.clear();
  }

  static List<MarkdownRenderNode> _renderNodesFromDocument(
    MarkdownDocument document,
    String source,
  ) {
    return document.blocks.map((MarkdownBlockNode block) {
      final String raw = source.substring(block.start, block.end);
      final int startRow = _rowForOffset(source, block.start);
      final int endRow = _rowForOffset(source, block.end);
      return MarkdownRenderNode(
        type: _fallbackNodeType(block),
        depth: 0,
        startByte: block.start,
        endByte: block.end,
        startRow: startRow,
        endRow: endRow,
        raw: raw,
        content: _fallbackNodeContent(block),
      );
    }).toList(growable: false);
  }

  static String _fallbackNodeType(MarkdownBlockNode block) {
    if (block is GenericBlockNode) {
      return block.type;
    }
    if (block is HeadingNode) {
      return block.type;
    }
    if (block is ParagraphNode) {
      return 'paragraph';
    }
    if (block is CodeFenceNode) {
      return 'fenced_code_block';
    }
    if (block is ListNode) {
      return 'list';
    }
    return 'paragraph';
  }

  static String _fallbackNodeContent(MarkdownBlockNode block) {
    if (block is GenericBlockNode) {
      return block.content;
    }
    if (block is HeadingNode) {
      return block.text;
    }
    if (block is ParagraphNode) {
      return block.text;
    }
    if (block is CodeFenceNode) {
      return block.code;
    }
    if (block is ListNode) {
      return block.items.map((ListItemNode item) => item.text).join('\n');
    }
    return '';
  }

  static int _rowForOffset(String source, int offset) {
    final int clamped = offset.clamp(0, source.length).toInt();
    int row = 0;
    for (int i = 0; i < clamped; i++) {
      if (source.codeUnitAt(i) == 0x0a) {
        row += 1;
      }
    }
    return row;
  }
}

/// Preferred parser name for streamed markdown sources.
class MarkdownStreamParser extends StreamingMarkdownParseWorker {}
