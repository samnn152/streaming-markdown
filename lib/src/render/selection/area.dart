part of '../view.dart';

class _MarkdownSelectionArea extends StatefulWidget {
  const _MarkdownSelectionArea({
    required this.projection,
    required this.child,
  });

  final _MarkdownSelectionProjection projection;
  final Widget child;

  @override
  State<_MarkdownSelectionArea> createState() => _MarkdownSelectionAreaState();
}

class _MarkdownSelectionAreaState extends State<_MarkdownSelectionArea> {
  SelectedContent? _selectedContent;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (
        BuildContext context,
        SelectableRegionState selectableRegionState,
      ) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: selectableRegionState.contextMenuButtonItems
              .map((ContextMenuButtonItem item) {
            if (item.type != ContextMenuButtonType.copy) {
              return item;
            }
            return ContextMenuButtonItem(
              type: item.type,
              label: item.label,
              onPressed: () {
                _copyMarkdownSelection();
                selectableRegionState.hideToolbar();
              },
            );
          }).toList(growable: false),
        );
      },
      onSelectionChanged: (SelectedContent? content) {
        _selectedContent = content;
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (CopySelectionTextIntent intent) {
              _copyMarkdownSelection();
              return null;
            },
          ),
        },
        child: widget.child,
      ),
    );
  }

  void _copyMarkdownSelection() {
    final String plainText = _selectedContent?.plainText ?? '';
    final String markdownText =
        widget.projection.markdownForSelectedPlainText(plainText);
    if (markdownText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: markdownText));
    }
  }
}
