import 'dart:async';
import 'dart:isolate';

import '../model/block_nodes.dart';
import '../model/render_node.dart';
import '../native/incremental_parser.dart';
import '../native/symbols.dart';
import '../parser/rope_markdown_parser.dart';
import '../model/rope.dart';

part 'parse_result.dart';
part 'parse_isolate.dart';

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

  /// Time spent warming parser symbols/session on the current isolate.
  final Duration currentIsolateTime;

  /// Time spent warming an isolate-backed [StreamingMarkdownParseWorker].
  final Duration? workerTime;

  /// End-to-end warm-up time.
  final Duration totalTime;
}

/// Warms parser resources before the first visible markdown render.
///
/// This touches the native incremental parser on the current isolate when the
/// native library is available. Set [includeWorker] to also start and dispose a
/// temporary isolate-backed parser so the async worker path pays its setup cost
/// before user-visible rendering.
Future<StreamingMarkdownWarmUpResult> warmUpStreamingMarkdownParser({
  bool includeWorker = false,
}) async {
  final Stopwatch totalWatch = Stopwatch()..start();
  final Stopwatch currentWatch = Stopwatch()..start();
  bool nativeAvailable = isStreamingMarkdownNativeLibraryAvailable;

  if (nativeAvailable) {
    NativeIncrementalMarkdownParser? parser;
    try {
      parser = NativeIncrementalMarkdownParser.create();
      parser.setText('');
      parser.blockCount();
    } catch (_) {
      nativeAvailable = false;
    } finally {
      parser?.dispose();
    }
  }
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
    nativeAvailable: nativeAvailable,
    currentIsolateTime: currentWatch.elapsed,
    workerTime: workerTime,
    totalTime: totalWatch.elapsed,
  );
}

/// Isolate-backed markdown parse worker.
///
/// Use [replace] for full snapshots, [append] for streamed chunks, or [parse]
/// when the operation is selected at runtime.
class StreamingMarkdownParseWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _sendPort;
  int _nextRequestId = 1;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};

  /// Starts the background isolate and parser session.
  Future<void> start() async {
    if (_sendPort != null) {
      return;
    }

    final ReceivePort port = ReceivePort();
    _receivePort = port;

    final Completer<SendPort> ready = Completer<SendPort>();
    _subscription = port.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) {
          ready.complete(message);
        }
        return;
      }

      if (message is Map<dynamic, dynamic>) {
        _handleMessage(message);
      }
    });

    _isolate = await Isolate.spawn(_parseWorkerMain, port.sendPort);
    _sendPort = await ready.future;
  }

  /// Parses [text] using a typed [operation].
  ///
  /// Set [includeNodes] to `true` when the result will be rendered. When it is
  /// `false`, the result only contains parser statistics.
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

  /// Replaces the current parser buffer with [markdown].
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

  /// Appends [chunk] to the current parser buffer.
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

  /// Sends a legacy string-based parse request and awaits normalized results.
  ///
  /// Prefer [parse], [replace], or [append] in new code.
  Future<StreamingMarkdownParseResult> request({
    required String op,
    required String text,
    required bool includeNodes,
  }) async {
    final SendPort? sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('Parse worker is not started');
    }

    final int id = _nextRequestId++;
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _pending[id] = completer;

    sendPort.send(<String, Object?>{
      'id': id,
      'op': op,
      'text': text,
      'includeNodes': includeNodes,
    });

    final Map<String, Object?> rawResult = await completer.future;
    return StreamingMarkdownParseResult(
      basicBlockCount: _intValue(rawResult['basicBlockCount']),
      inlineTypeCount: _intValue(rawResult['inlineTypeCount']),
      nativeAvailable: rawResult['nativeAvailable'] == true,
      mode: (rawResult['mode'] as String?) ?? '-',
      nodesIncluded: rawResult['nodesIncluded'] == true,
      updateTime: Duration(microseconds: _intValue(rawResult['updateUs'])),
      statsTime: Duration(microseconds: _intValue(rawResult['statsUs'])),
      totalTime: Duration(microseconds: _intValue(rawResult['totalUs'])),
      visibleNodes: _nodeEntriesFromResult(rawResult['visibleNodes']),
      renderNodes: _nodeEntriesFromResult(rawResult['renderNodes']),
    );
  }

  void _handleMessage(Map<dynamic, dynamic> message) {
    final int id = _msgInt(message['id']);
    final Completer<Map<String, Object?>>? completer = _pending.remove(id);
    if (completer == null) {
      return;
    }

    final Object? error = message['error'];
    if (error != null) {
      completer.completeError(StateError(error.toString()));
      return;
    }

    final Object? rawResult = message['result'];
    if (rawResult is! Map<dynamic, dynamic>) {
      completer.completeError(
        const FormatException('Worker returned an invalid result payload'),
      );
      return;
    }

    completer.complete(
      rawResult.map((dynamic key, dynamic value) {
        return MapEntry(key.toString(), value);
      }),
    );
  }

  /// Disposes the worker isolate and clears pending requests.
  void dispose() {
    final SendPort? sendPort = _sendPort;
    if (sendPort != null) {
      sendPort.send(<String, Object?>{'op': 'dispose'});
    }

    for (final Completer<Map<String, Object?>> completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Parse worker disposed'));
      }
    }
    _pending.clear();

    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  static List<MarkdownRenderNode> _nodeEntriesFromResult(Object? rawNodes) {
    if (rawNodes is! List<dynamic>) {
      return <MarkdownRenderNode>[];
    }

    return rawNodes
        .whereType<Map<dynamic, dynamic>>()
        .map(MarkdownRenderNode.fromDynamicMap)
        .toList(growable: false);
  }

  static int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

/// Parser backend used by [MarkdownSyncParser].
enum MarkdownSyncParserBackend {
  /// Use the native parser when available, otherwise fall back to pure Dart.
  auto,

  /// Force the native parser. Falls back to pure Dart if native loading fails.
  native,

  /// Force the pure-Dart rope parser.
  dart,
}

/// Synchronous markdown parser for short documents and first-frame rendering.
///
/// Unlike [StreamingMarkdownParseWorker], this parser runs on the current
/// isolate and returns immediately. Prefer the isolate-backed worker for long
/// or continuously streamed markdown, and use this class when avoiding an
/// extra async frame is more important than moving parse work off the UI
/// isolate.
class MarkdownSyncParser {
  /// Creates a parser session.
  MarkdownSyncParser({
    MarkdownSyncParserBackend backend = MarkdownSyncParserBackend.auto,
  }) : _backend = backend {
    if (backend != MarkdownSyncParserBackend.dart &&
        isStreamingMarkdownNativeLibraryAvailable) {
      try {
        _native = NativeIncrementalMarkdownParser.create();
        _nativeAvailable = true;
      } catch (_) {
        _native = null;
        _nativeAvailable = false;
      }
    }
  }

  final MarkdownSyncParserBackend _backend;
  NativeIncrementalMarkdownParser? _native;
  bool _nativeAvailable = false;
  final RopeString _fallbackRope = RopeString();

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

    String mode;
    final NativeIncrementalMarkdownParser? native = _native;
    if (_nativeAvailable && native != null) {
      final bool ok =
          op == 'append' ? native.appendText(text) : native.setText(text);
      if (!ok) {
        throw StateError('Native incremental parse failed');
      }
      mode = op == 'append' ? 'sync-incremental-append' : 'sync-full-set';
    } else {
      if (op == 'append') {
        _fallbackRope.append(text);
        mode = _backend == MarkdownSyncParserBackend.dart
            ? 'sync-dart-append'
            : 'sync-fallback-append';
      } else {
        _fallbackRope
          ..clear()
          ..append(text);
        mode = _backend == MarkdownSyncParserBackend.dart
            ? 'sync-dart-set'
            : 'sync-fallback-set';
      }
    }

    updateWatch.stop();

    final Stopwatch statsWatch = Stopwatch()..start();
    late final int blockCount;
    late final int inlineTypeCount;
    late final List<MarkdownRenderNode> renderNodes;

    if (_nativeAvailable && native != null) {
      blockCount = native.blockCount();
      inlineTypeCount = native.inlineTypeCount();
      renderNodes = includeNodes
          ? _nodesFromMaps(_normalizeVisibleNodes(native.blockNodes()))
          : const <MarkdownRenderNode>[];
    } else {
      final MarkdownDocument document =
          const RopeMarkdownParser().parse(_fallbackRope);
      blockCount = document.blocks.length;
      inlineTypeCount = 0;
      renderNodes = includeNodes
          ? _renderNodesFromDocument(document, _fallbackRope.toString())
          : const <MarkdownRenderNode>[];
    }

    statsWatch.stop();
    totalWatch.stop();

    return StreamingMarkdownParseResult(
      basicBlockCount: blockCount,
      inlineTypeCount: inlineTypeCount,
      nativeAvailable: _nativeAvailable,
      mode: mode,
      nodesIncluded: includeNodes,
      updateTime: updateWatch.elapsed,
      statsTime: statsWatch.elapsed,
      totalTime: totalWatch.elapsed,
      visibleNodes: renderNodes,
      renderNodes: renderNodes,
    );
  }

  /// Disposes the native parser session and clears fallback state.
  void dispose() {
    _native?.dispose();
    _native = null;
    _nativeAvailable = false;
    _fallbackRope.clear();
  }

  static List<MarkdownRenderNode> _nodesFromMaps(
    List<Map<String, Object>> maps,
  ) {
    return maps.map(MarkdownRenderNode.fromDynamicMap).toList(growable: false);
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
///
/// This class is intentionally a thin compatibility layer over
/// [StreamingMarkdownParseWorker]. New code can use [MarkdownStreamParser] to
/// make the parser role clearer while existing `0.2.x` code can keep using
/// [StreamingMarkdownParseWorker].
class MarkdownStreamParser extends StreamingMarkdownParseWorker {}
