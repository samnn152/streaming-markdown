part of '../view.dart';

class _HtmlBlockCard extends StatelessWidget {
  const _HtmlBlockCard({
    required this.html,
    required this.onLinkTap,
    required this.paragraphTextStyle,
  });

  final String html;
  final ValueChanged<String> onLinkTap;
  final TextStyle? paragraphTextStyle;

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final html_dom.DocumentFragment fragment = html_parser.parseFragment(html);
    final _HtmlBlockRenderer renderer = _HtmlBlockRenderer(
      context: context,
      onLinkTap: onLinkTap,
      paragraphTextStyle: paragraphTextStyle,
    );
    final List<Widget> blocks = renderer.buildBlocks(fragment.nodes);
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _HtmlBlockRenderer.withSpacing(blocks, 8),
      ),
    );
  }
}
