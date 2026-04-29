part of '../view.dart';

typedef _BlockBuilder = Widget Function(
  BuildContext context,
  MarkdownRenderNode node,
  Map<String, String> linkReferences,
  Map<String, int> footnoteNumbers,
);

class _SequencedBlockList extends StatefulWidget {
  const _SequencedBlockList({
    required this.blocks,
    required this.sliver,
    required this.padding,
    required this.blockSpacing,
    required this.tokenArrivalDelay,
    required this.paused,
    required this.blockIdentityBuilder,
    required this.blockBuilder,
    this.onWait,
  });

  final List<MarkdownRenderNode> blocks;
  final bool sliver;
  final EdgeInsetsGeometry padding;
  final double blockSpacing;
  final Duration tokenArrivalDelay;
  final bool paused;
  final VoidCallback? onWait;
  final String Function(MarkdownRenderNode node) blockIdentityBuilder;
  final Widget Function(BuildContext context, MarkdownRenderNode node)
      blockBuilder;

  @override
  State<_SequencedBlockList> createState() => _SequencedBlockListState();
}
