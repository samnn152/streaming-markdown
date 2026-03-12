import 'dart:async';
import 'dart:isolate';

import 'markdown_nodes.dart';
import 'markdown_render_node.dart';
import 'native_incremental_markdown_parser.dart';
import 'native_symbols.dart';
import 'rope_markdown_parser.dart';
import 'rope_string.dart';

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

class StreamingMarkdownParseWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _sendPort;
  int _nextRequestId = 1;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};

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

void _parseWorkerMain(SendPort mainSendPort) {
  final ReceivePort commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  NativeIncrementalMarkdownParser? incremental;
  bool nativeAvailable = false;
  final RopeString fallbackRope = RopeString();

  if (isStreamingMarkdownNativeLibraryAvailable) {
    try {
      incremental = NativeIncrementalMarkdownParser.create();
      nativeAvailable = true;
    } catch (_) {
      incremental = null;
      nativeAvailable = false;
    }
  }

  commandPort.listen((dynamic rawMessage) {
    if (rawMessage is! Map<dynamic, dynamic>) {
      return;
    }

    final String op = (rawMessage['op'] as String?) ?? '';
    if (op == 'dispose') {
      incremental?.dispose();
      commandPort.close();
      return;
    }

    final int id = _msgInt(rawMessage['id']);
    final String text = (rawMessage['text'] as String?) ?? '';
    final bool includeNodes = rawMessage['includeNodes'] == true;

    try {
      final Stopwatch totalWatch = Stopwatch()..start();
      final Stopwatch updateWatch = Stopwatch()..start();

      String mode = 'fallback-dart';
      if (nativeAvailable && incremental != null) {
        final bool ok = op == 'append'
            ? incremental.appendText(text)
            : incremental.setText(text);
        if (!ok) {
          throw StateError('Native incremental parse failed');
        }
        mode = op == 'append' ? 'incremental-append' : 'full-set';
      } else {
        if (op == 'append') {
          fallbackRope.append(text);
          mode = 'fallback-append';
        } else {
          fallbackRope
            ..clear()
            ..append(text);
          mode = 'fallback-set';
        }
      }

      updateWatch.stop();

      final Stopwatch statsWatch = Stopwatch()..start();
      int blockCount;
      int inlineTypeCount;
      List<Map<String, Object>> visibleNodes;
      List<Map<String, Object>> renderNodes;

      if (nativeAvailable && incremental != null) {
        blockCount = incremental.blockCount();
        inlineTypeCount = incremental.inlineTypeCount();
        if (includeNodes) {
          renderNodes = _normalizeVisibleNodes(incremental.blockNodes());
          visibleNodes = renderNodes;
        } else {
          renderNodes = <Map<String, Object>>[];
          visibleNodes = <Map<String, Object>>[];
        }
      } else {
        final MarkdownDocument document = const RopeMarkdownParser().parse(
          fallbackRope,
        );
        blockCount = document.blocks.length;
        inlineTypeCount = 0;
        renderNodes = <Map<String, Object>>[];
        visibleNodes = <Map<String, Object>>[];
      }

      statsWatch.stop();
      totalWatch.stop();

      mainSendPort.send(<String, Object?>{
        'id': id,
        'result': <String, Object?>{
          'basicBlockCount': blockCount,
          'inlineTypeCount': inlineTypeCount,
          'nativeAvailable': nativeAvailable,
          'mode': mode,
          'nodesIncluded': includeNodes,
          'updateUs': updateWatch.elapsedMicroseconds,
          'statsUs': statsWatch.elapsedMicroseconds,
          'totalUs': totalWatch.elapsedMicroseconds,
          'visibleNodes': visibleNodes,
          'renderNodes': renderNodes,
        },
      });
    } catch (error, stackTrace) {
      mainSendPort.send(<String, Object?>{
        'id': id,
        'error': '$error\n$stackTrace',
      });
    }
  });
}

int _msgInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

List<Map<String, Object>> _normalizeVisibleNodes(
  List<Map<String, Object>> rawNodes,
) {
  final List<Map<String, Object>> out = <Map<String, Object>>[];
  for (final Map<String, Object> node in rawNodes) {
    final String type = (node['type'] as String?) ?? 'unknown';
    final String raw = (node['raw'] as String?) ?? '';
    final String content = _meaningfulContent(type, raw);

    if (_shouldDropNode(type, content, raw)) {
      continue;
    }

    out.add(<String, Object>{...node, 'content': content});
  }
  return out;
}

String _meaningfulContent(String type, String raw) {
  String content = raw.replaceAll('\r', '').trim();

  switch (type) {
    case 'atx_heading':
    case 'setext_heading':
      content = content
          .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '')
          .replaceFirst(RegExp(r'\s*#{1,}\s*$'), '');
      break;
    case 'list_item':
      content = content.replaceFirst(
        RegExp(r'^\s*(?:[-+*]|\d+[.)])\s*(?:\[[ xX]\]\s*)?'),
        '',
      );
      break;
    case 'block_quote':
      content = content
          .split('\n')
          .map((String line) => line.replaceFirst(RegExp(r'^\s*>\s?'), ''))
          .join(' ');
      break;
    case 'fenced_code_block':
      final List<String> lines = content.split('\n');
      if (lines.isNotEmpty &&
          RegExp(r'^\s*(```+|~~~+)').hasMatch(lines.first)) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty &&
          RegExp(r'^\s*(```+|~~~+)\s*$').hasMatch(lines.last)) {
        lines.removeLast();
      }
      content = lines.join(' ');
      break;
    case 'code_span':
      content = content
          .replaceFirst(RegExp(r'^`+'), '')
          .replaceFirst(RegExp(r'`+$'), '');
      break;
    case 'emphasis':
    case 'strong_emphasis':
    case 'strikethrough':
      content = content.replaceFirst(RegExp(r'^[_*~\s]+|[_*~\s]+$'), '');
      break;
    case 'inline_link':
    case 'full_reference_link':
    case 'collapsed_reference_link':
    case 'shortcut_link':
    case 'image':
      final RegExpMatch? match = RegExp(r'\[([^\]]+)\]').firstMatch(content);
      if (match != null) {
        content = match.group(1)!;
      }
      break;
    default:
      break;
  }

  content = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (RegExp(r'^[`*_~#>\-\+\|\[\]\(\){}.!?:;=/\\\s]+$').hasMatch(content)) {
    return '';
  }

  return content;
}

bool _shouldDropNode(String type, String content, String raw) {
  if (type == 'document' || type == 'section') {
    return true;
  }

  if (type.contains('marker') ||
      type.contains('delimiter') ||
      type == 'block_continuation' ||
      type == 'pipe_table_delimiter_row') {
    return true;
  }

  if (_keepNodeWhenContentEmpty(type)) {
    return false;
  }

  if (raw.trim().isEmpty) {
    return content.isEmpty;
  }

  return content.isEmpty;
}

bool _keepNodeWhenContentEmpty(String type) {
  switch (type) {
    case 'thematic_break':
    case 'fenced_code_block':
    case 'indented_code_block':
    case 'block_quote':
    case 'list':
    case 'list_item':
    case 'pipe_table':
    case 'table':
    case 'html_block':
    case 'front_matter':
      return true;
    default:
      return false;
  }
}
