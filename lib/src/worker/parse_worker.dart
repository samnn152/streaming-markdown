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

/// Preferred parser name for streamed markdown sources.
///
/// This class is intentionally a thin compatibility layer over
/// [StreamingMarkdownParseWorker]. New code can use [MarkdownStreamParser] to
/// make the parser role clearer while existing `0.2.x` code can keep using
/// [StreamingMarkdownParseWorker].
class MarkdownStreamParser extends StreamingMarkdownParseWorker {}
