part of '../view.dart';

extension _StreamingMarkdownBlockTextParsing on StreamingMarkdownRenderView {
  _ParsedList _parseListNode(MarkdownRenderNode node) {
    final List<String> lines = _normalizedRaw(node.raw).split('\n');
    final List<_ParsedListItem> items = <_ParsedListItem>[];

    for (final String line in lines) {
      final RegExpMatch? markerMatch = RegExp(
        r'^(\s*)([-+*]|\d+[.)])\s+(.*)$',
      ).firstMatch(line);
      if (markerMatch == null) {
        if (items.isNotEmpty && line.trim().isNotEmpty) {
          final _ParsedListItem last = items.removeLast();
          items.add(
            _ParsedListItem(
              level: last.level,
              ordered: last.ordered,
              order: last.order,
              taskState: last.taskState,
              text: '${last.text} ${line.trim()}',
              stableKey: last.stableKey,
            ),
          );
        }
        continue;
      }

      final String marker = markerMatch.group(2)!;
      String body = markerMatch.group(3)!.trimRight();
      bool? taskState;
      final RegExpMatch? taskMatch = RegExp(
        r'^\[([ xX])\]\s*(.*)$',
      ).firstMatch(body);
      if (taskMatch != null) {
        taskState = taskMatch.group(1)!.toLowerCase() == 'x';
        body = taskMatch.group(2)!;
      }

      final int level = (markerMatch.group(1)!.length / 2).floor();
      final bool ordered = RegExp(r'^\d').hasMatch(marker);
      final int order = ordered
          ? int.tryParse(marker.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1
          : 0;

      items.add(
        _ParsedListItem(
          level: level,
          ordered: ordered,
          order: order,
          taskState: taskState,
          text: body.trim(),
          stableKey: 'line_${items.length}',
        ),
      );
    }

    return _ParsedList(items: items);
  }

  _CalloutData? _parseCallout(String text) {
    final List<String> lines = text.split('\n');
    if (lines.isEmpty) {
      return null;
    }

    final RegExpMatch? match = RegExp(
      r'^\s*\[!(\w+)\]\s*(.*)$',
    ).firstMatch(lines.first);
    if (match == null) {
      return null;
    }

    final String kind = match.group(1)!.toLowerCase();
    final String title = match.group(2)!.trim().isEmpty
        ? kind[0].toUpperCase() + kind.substring(1)
        : match.group(2)!.trim();
    final String body = lines.skip(1).join('\n').trim();

    return _CalloutData(kind: kind, title: title, body: body);
  }

  Color _calloutColor(String? kind) {
    switch (kind) {
      case 'note':
        return const Color(0xFF58A6FF);
      case 'tip':
        return const Color(0xFF3FB950);
      case 'warning':
        return const Color(0xFFD29922);
      case 'important':
        return const Color(0xFFBC8CFF);
      case 'caution':
        return const Color(0xFFF85149);
      default:
        return const Color(0xFF8B949E);
    }
  }

  IconData _calloutIcon(String kind) {
    switch (kind) {
      case 'note':
        return Icons.info_outline;
      case 'tip':
        return Icons.lightbulb_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'important':
        return Icons.priority_high;
      case 'caution':
        return Icons.error_outline;
      default:
        return Icons.notes;
    }
  }

  String _quoteText(MarkdownRenderNode node) {
    return _normalizedRaw(node.raw)
        .split('\n')
        .map((String line) => line.replaceFirst(RegExp(r'^\s*>\s?'), ''))
        .join('\n')
        .trim();
  }

  String _codeText(MarkdownRenderNode node) {
    final String raw = _normalizedRaw(node.raw);
    if (node.type == 'fenced_code_block') {
      final List<String> lines = raw.split('\n');
      if (lines.isNotEmpty &&
          RegExp(r'^\s*(```+|~~~+)').hasMatch(lines.first)) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty &&
          RegExp(r'^\s*(```+|~~~+)\s*$').hasMatch(lines.last)) {
        lines.removeLast();
      }
      return lines.join('\n').trimRight();
    }
    return raw;
  }

  String _codeLanguage(String raw) {
    final RegExpMatch? match = RegExp(
      r'^\s*(```+|~~~+)\s*([A-Za-z0-9_+\-\.#]*)',
      multiLine: true,
    ).firstMatch(raw);
    if (match == null) {
      return '';
    }
    return match.group(2)!.trim();
  }
}
