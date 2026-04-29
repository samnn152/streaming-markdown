part of '../view.dart';

extension _StreamingMarkdownBlockPipeline on StreamingMarkdownRenderView {
  List<MarkdownRenderNode> _collectRenderableBlocks(
    List<MarkdownRenderNode> nodes,
  ) {
    if (nodes.isEmpty) {
      return <MarkdownRenderNode>[];
    }

    final List<MarkdownRenderNode> blockNodes = nodes
        .where((MarkdownRenderNode node) => _isRenderableBlockNode(node.type))
        .toList(growable: false);
    if (blockNodes.isEmpty) {
      return <MarkdownRenderNode>[];
    }

    final List<MarkdownRenderNode> sorted = blockNodes.toList(growable: false)
      ..sort((MarkdownRenderNode a, MarkdownRenderNode b) {
        final int byStart = a.startByte.compareTo(b.startByte);
        if (byStart != 0) {
          return byStart;
        }
        final int byEnd = b.endByte.compareTo(a.endByte);
        if (byEnd != 0) {
          return byEnd;
        }
        return a.depth.compareTo(b.depth);
      });
    final List<MarkdownRenderNode> normalized = _mergeOrphanTableFragments(
      sorted,
    );

    final Set<String> seenSpans = <String>{};
    final List<MarkdownRenderNode> out = <MarkdownRenderNode>[];
    MarkdownRenderNode? lastContainer;

    for (final MarkdownRenderNode node in normalized) {
      final String spanKey = '${node.startByte}:${node.endByte}:${node.type}';
      if (!seenSpans.add(spanKey)) {
        continue;
      }

      if (lastContainer != null &&
          node.startByte >= lastContainer.startByte &&
          node.endByte <= lastContainer.endByte &&
          node.depth > lastContainer.depth) {
        continue;
      }

      out.add(node);
      if (_containerConsumesChildren(node.type)) {
        lastContainer = node;
      } else if (lastContainer != null &&
          node.endByte > lastContainer.endByte) {
        lastContainer = null;
      }
    }

    return out;
  }

  List<MarkdownRenderNode> _mergeOrphanTableFragments(
    List<MarkdownRenderNode> sorted,
  ) {
    final List<MarkdownRenderNode> out = <MarkdownRenderNode>[];
    int i = 0;
    while (i < sorted.length) {
      final MarkdownRenderNode node = sorted[i];
      if (!_isTableFragmentNode(node.type)) {
        out.add(node);
        i += 1;
        continue;
      }
      if (_isTableFragmentCoveredByContainer(node, sorted)) {
        i += 1;
        continue;
      }

      final List<MarkdownRenderNode> fragments = <MarkdownRenderNode>[node];
      int j = i + 1;
      while (j < sorted.length) {
        final MarkdownRenderNode candidate = sorted[j];
        if (!_isTableFragmentNode(candidate.type) ||
            _isTableFragmentCoveredByContainer(candidate, sorted)) {
          break;
        }
        final MarkdownRenderNode previous = fragments.last;
        if (candidate.startRow > previous.endRow + 1) {
          break;
        }
        fragments.add(candidate);
        j += 1;
      }

      final MarkdownRenderNode synthesized = _synthesizeTableNodeFromFragments(
        fragments,
      );
      final _ParsedTable? parsed = _parseMarkdownTable(
        _normalizedRaw(synthesized.raw),
        allowLooseWithoutDelimiter: true,
        minLooseRowsWithoutDelimiter: 2,
      );
      if (parsed == null) {
        out.add(node);
        i += 1;
        continue;
      }

      out.add(synthesized);
      i = j;
    }
    return out;
  }

  MarkdownRenderNode _synthesizeTableNodeFromFragments(
    List<MarkdownRenderNode> fragments,
  ) {
    int startByte = fragments.first.startByte;
    int endByte = fragments.first.endByte;
    int startRow = fragments.first.startRow;
    int endRow = fragments.first.endRow;
    int depth = fragments.first.depth;
    final StringBuffer raw = StringBuffer();
    for (int i = 0; i < fragments.length; i++) {
      final MarkdownRenderNode fragment = fragments[i];
      if (fragment.startByte < startByte) {
        startByte = fragment.startByte;
      }
      if (fragment.endByte > endByte) {
        endByte = fragment.endByte;
      }
      if (fragment.startRow < startRow) {
        startRow = fragment.startRow;
      }
      if (fragment.endRow > endRow) {
        endRow = fragment.endRow;
      }
      if (fragment.depth < depth) {
        depth = fragment.depth;
      }

      final String line = _normalizedRaw(fragment.raw).trim();
      if (line.isNotEmpty) {
        if (raw.isNotEmpty) {
          raw.writeln();
        }
        raw.write(line);
      }
    }

    return MarkdownRenderNode(
      type: 'pipe_table',
      depth: depth,
      startByte: startByte,
      endByte: endByte,
      startRow: startRow,
      endRow: endRow,
      raw: raw.toString(),
      content: raw.toString(),
    );
  }

  bool _isTableFragmentCoveredByContainer(
    MarkdownRenderNode node,
    List<MarkdownRenderNode> all,
  ) {
    for (final MarkdownRenderNode candidate in all) {
      if (!_isTableContainerNode(candidate.type)) {
        continue;
      }
      if (candidate.startByte <= node.startByte &&
          candidate.endByte >= node.endByte &&
          candidate.depth <= node.depth) {
        return true;
      }
    }
    return false;
  }

  bool _isTableContainerNode(String type) {
    return type == 'pipe_table' || type == 'table';
  }

  bool _isTableFragmentNode(String type) {
    return type == 'pipe_table_header' ||
        type == 'pipe_table_row' ||
        type == 'pipe_table_delimiter_row';
  }

  bool _isRenderableBlockNode(String type) {
    switch (type) {
      case 'atx_heading':
      case 'setext_heading':
      case 'paragraph':
      case 'fenced_code_block':
      case 'indented_code_block':
      case 'block_quote':
      case 'list':
      case 'thematic_break':
      case 'html_block':
      case 'pipe_table':
      case 'table':
      case 'pipe_table_header':
      case 'pipe_table_row':
      case 'pipe_table_delimiter_row':
      case 'footnote_definition':
      case 'link_reference_definition':
      case 'front_matter':
        return true;
      default:
        return type.endsWith('_block') || type.endsWith('_heading');
    }
  }

  bool _containerConsumesChildren(String type) {
    return type == 'block_quote' ||
        type == 'list' ||
        type == 'fenced_code_block' ||
        type == 'indented_code_block' ||
        type == 'pipe_table' ||
        type == 'table' ||
        type == 'html_block' ||
        type == 'front_matter';
  }
}
