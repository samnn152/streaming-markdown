part of 'parse_worker.dart';

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
    case 'list':
      content = content
          .split('\n')
          .map(
            (String line) => line.replaceFirst(
              RegExp(r'^\s*(?:[-+*]|\d+[.)])\s*(?:\[[ xX]\]\s*)?'),
              '',
            ),
          )
          .where((String line) => line.trim().isNotEmpty)
          .join(' ');
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
    case 'footnote_definition':
      content = content.replaceFirst(
        RegExp(r'^\s{0,3}\[\^[^\]]+\]:\s*'),
        '',
      );
      break;
    case 'link_reference_definition':
      content = content.replaceFirst(
        RegExp(r'^\s{0,3}\[[^\]]+\]:\s*'),
        '',
      );
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

  if (type == 'pipe_table_delimiter_row') {
    return false;
  }

  if (type.contains('marker') ||
      type.contains('delimiter') ||
      type == 'block_continuation') {
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
    case 'pipe_table_delimiter_row':
    case 'table':
    case 'html_block':
    case 'front_matter':
      return true;
    default:
      return false;
  }
}
