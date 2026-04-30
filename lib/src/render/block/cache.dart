part of '../view.dart';

extension _StreamingMarkdownBlockCache on StreamingMarkdownRenderView {
  String _blockIdentity(MarkdownRenderNode node) {
    return '${node.type}:${node.startByte}:${node.depth}';
  }

  String _tableSnapshotKey(MarkdownRenderNode node) {
    return '${node.startByte}:${node.startRow}:${node.depth}';
  }

  void _rememberTableSnapshot(MarkdownRenderNode node, _ParsedTable table) {
    if (!_tableHasContent(table)) {
      return;
    }
    final String key = _tableSnapshotKey(node);
    StreamingMarkdownRenderView._tableSnapshotCache[key] = table;
    if (StreamingMarkdownRenderView._tableSnapshotCache.length <=
        StreamingMarkdownRenderView._tableSnapshotCacheLimit) {
      return;
    }
    final String firstKey =
        StreamingMarkdownRenderView._tableSnapshotCache.keys.first;
    StreamingMarkdownRenderView._tableSnapshotCache.remove(firstKey);
  }

  _ParsedTable? _readTableSnapshot(MarkdownRenderNode node) {
    return StreamingMarkdownRenderView
        ._tableSnapshotCache[_tableSnapshotKey(node)];
  }

  bool _tableHasContent(_ParsedTable table) {
    for (final String cell in table.headers) {
      if (cell.trim().isNotEmpty) {
        return true;
      }
    }
    for (final List<String> row in table.rows) {
      for (final String cell in row) {
        if (cell.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  String _blockSignature(
    MarkdownRenderNode node,
    String refsDigest,
    String renderConfigDigest,
  ) {
    return '${node.type}:${node.startByte}:${node.endByte}:${node.startRow}:${node.endRow}:${node.raw.hashCode}:$refsDigest:$renderConfigDigest';
  }

  String _renderConfigDigest(BuildContext context) {
    final Duration resolvedFade = _resolvedTokenFadeInDuration();
    final StringBuffer buffer = StringBuffer()
      ..write('render-behavior:footnote-lines-v3')
      ..write(':')
      ..write(tokenArrivalDelay.inMicroseconds)
      ..write(':')
      ..write(onTokenArrivalWait.hashCode)
      ..write(':')
      ..write(onTokenFadeInEnd.hashCode)
      ..write(':')
      ..write(resolvedFade.inMicroseconds)
      ..write(':')
      ..write(tokenFadeInCurve)
      ..write(':')
      ..write(tokenAnimationBuilder.hashCode)
      ..write(':')
      ..write(tokenCompaction)
      ..write(':')
      ..write(allowUnclosedInlineDelimiters)
      ..write(':')
      ..write(debugTokenHighlight)
      ..write(':')
      ..write(enableTextSelection)
      ..write(':')
      ..write(sliver)
      ..write(':')
      ..write(padding.hashCode)
      ..write(':')
      ..write(markdownTheme.hashCode)
      ..write(':')
      ..write(customBlockBuilder.hashCode)
      ..write(':')
      ..write(onLinkTap.hashCode)
      ..write(':')
      ..write(Theme.of(context).hashCode);
    return buffer.toString().hashCode.toString();
  }
}
