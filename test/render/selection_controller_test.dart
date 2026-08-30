import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ClearSelectionEvent, RenderParagraph, Selectable;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'controller preserves direction and clamps to grapheme boundaries',
      (WidgetTester tester) async {
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);
    const String source = 'A👨‍👩‍👧‍👦B';

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
        ),
      ),
    );

    controller.selection = const TextSelection(
      baseOffset: source.length,
      extentOffset: 6,
      isDirectional: true,
    );
    expect(controller.selection.baseOffset, source.length);
    expect(controller.selection.extentOffset, 1);
    expect(controller.selection.isDirectional, isTrue);
  });

  testWidgets('controller restores an endpoint when a streamed block remounts',
      (WidgetTester tester) async {
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _node('Selected block one.', startByte: 0),
      _node('Selected block two.', startByte: 21),
    ];
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            update = setState;
            return AnimatedStreamingMarkdown(
              blocks: nodes,
              padding: EdgeInsets.zero,
              enableSelection: true,
              selectionController: controller,
            );
          },
        ),
      ),
    );

    final SelectableRegionState region =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(
      controller.value.selectedMarkdown,
      'Selected block one.\n\nSelected block two.',
      reason: 'initial select-all must be source-backed',
    );

    update(() {
      nodes = <MarkdownRenderNode>[
        _node('Selected block one.', startByte: 0),
      ];
    });
    await tester.pump();
    expect(controller.value.selectedMarkdown, 'Selected block one.');

    update(() {
      nodes = <MarkdownRenderNode>[
        _node('Selected block one.', startByte: 0),
        _node('Selected block two.', startByte: 21),
      ];
    });
    await tester.pump();
    expect(
      controller.value.selectedMarkdown,
      'Selected block one.\n\nSelected block two.',
      reason: 'the semantic endpoint lease must survive a transient shrink',
    );
  });

  testWidgets('sliver wrapper reveals and retains a controller selection',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AnimatedMarkdownSelectionController selectionController =
        AnimatedMarkdownSelectionController();
    final ScrollController scrollController = ScrollController();
    addTearDown(selectionController.dispose);
    addTearDown(scrollController.dispose);
    final List<MarkdownRenderNode> nodes = _paragraphNodes(30);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdownSelectionArea(
            controller: selectionController,
            child: CustomScrollView(
              controller: scrollController,
              slivers: <Widget>[
                AnimatedStreamingMarkdown(
                  blocks: nodes,
                  asSliver: true,
                  padding: EdgeInsets.zero,
                  enableSelection: true,
                  selectionController: selectionController,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final String source = selectionController.value.sourceText;
    expect(_richTextContaining(tester, 'Sliver block 29'), isNull);

    selectionController.selectAll();
    for (int frame = 0; frame < 6; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(selectionController.value.selectedMarkdown, source);
    expect(scrollController.offset, greaterThan(0));
    expect(_richTextContaining(tester, 'Sliver block 29'), isNotNull);

    scrollController.jumpTo(0);
    await tester.pump();
    expect(selectionController.value.selectedMarkdown, source);
  });

  testWidgets('sliver edge drag scrolls per frame and stops on release',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 140));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AnimatedMarkdownSelectionController selectionController =
        AnimatedMarkdownSelectionController();
    final ScrollController scrollController = ScrollController();
    int scrollUpdatesThisFrame = 0;
    int maximumScrollUpdatesPerFrame = 0;
    scrollController.addListener(() {
      scrollUpdatesThisFrame += 1;
    });
    addTearDown(selectionController.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdownSelectionArea(
            controller: selectionController,
            child: CustomScrollView(
              controller: scrollController,
              slivers: <Widget>[
                AnimatedStreamingMarkdown(
                  blocks: _paragraphNodes(24),
                  asSliver: true,
                  padding: EdgeInsets.zero,
                  enableSelection: true,
                  selectionController: selectionController,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph paragraph =
        _richTextContaining(tester, 'Sliver block 0')!;
    final TestGesture gesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(2, 8)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(const Offset(24, 138));
    for (int frame = 0; frame < 24; frame += 1) {
      scrollUpdatesThisFrame = 0;
      await tester.pump(const Duration(milliseconds: 16));
      if (scrollUpdatesThisFrame > maximumScrollUpdatesPerFrame) {
        maximumScrollUpdatesPerFrame = scrollUpdatesThisFrame;
      }
    }

    expect(scrollController.offset, greaterThan(0));
    expect(selectionController.value.hasSelection, isTrue);
    expect(
      selectionController.value.selectedMarkdown,
      startsWith('Sliver block 0'),
    );
    expect(
      maximumScrollUpdatesPerFrame,
      lessThanOrEqualTo(1),
      reason: 'one ScrollPosition must not receive competing auto-scroll '
          'updates in the same frame',
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    final double stoppedOffset = scrollController.offset;
    await tester.pump(const Duration(milliseconds: 32));
    expect(scrollController.offset, closeTo(stoppedOffset, 0.01));
  });

  testWidgets('pointer moves do not rebuild Markdown blocks',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);
    int blockBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown(
            blocks: <MarkdownRenderNode>[
              _node(
                'Pointer movement updates geometry without rebuilding this '
                'rendered block.',
                startByte: 0,
              ),
            ],
            padding: EdgeInsets.zero,
            enableSelection: true,
            selectionController: controller,
            blockBuilder: (
              BuildContext context,
              AnimatedMarkdownBlockContext block,
            ) {
              blockBuilds += 1;
              return block.defaultWidget;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final int buildsBeforeDrag = blockBuilds;
    final RenderParagraph paragraph =
        _richTextContaining(tester, 'Pointer movement')!;
    final Offset start = paragraph.localToGlobal(const Offset(2, 8));
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    for (int step = 1; step <= 8; step += 1) {
      await gesture.moveTo(start + Offset(step * 18, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.value.hasSelection, isTrue);
    expect(
      blockBuilds,
      buildsBeforeDrag,
      reason: 'active selection should update render geometry and paint only',
    );
    await gesture.up();
    await tester.pump();
  });

  testWidgets('transient geometry clears keep the active drag paint range',
      (WidgetTester tester) async {
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown(
            blocks: <MarkdownRenderNode>[
              _node(
                'A framework geometry transfer must never blank selection.',
                startByte: 0,
              ),
            ],
            padding: EdgeInsets.zero,
            enableSelection: true,
            selectionController: controller,
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph paragraph =
        _richTextContaining(tester, 'framework geometry')!;
    final Offset start = paragraph.localToGlobal(const Offset(2, 8));
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(start + const Offset(220, 0));
    await tester.pump(const Duration(milliseconds: 16));

    final Selectable selectedProxy = find
        .byWidgetPredicate(
          (Widget widget) =>
              widget.runtimeType.toString() == '_SelectableInlineTextProxy',
        )
        .evaluate()
        .map((Element element) => element.renderObject)
        .whereType<Selectable>()
        .firstWhere(
          (Selectable selectable) =>
              selectable.getSelectedContent()?.plainText.isNotEmpty ?? false,
        );
    final dynamic paintProxy = selectedProxy;
    final Object? paintRange = paintProxy.debugPaintSelectionRange as Object?;
    expect(paintRange, isNotNull);

    selectedProxy.dispatchSelectionEvent(const ClearSelectionEvent());

    expect(selectedProxy.getSelectedContent(), isNull);
    expect(
      paintProxy.debugPaintSelectionRange,
      paintRange,
      reason: 'paint must remain controller-owned while Flutter repartitions '
          'selection geometry',
    );

    await gesture.up();
    await tester.pump();
  });
}

MarkdownRenderNode _node(String raw, {required int startByte}) {
  return MarkdownRenderNode(
    type: 'paragraph',
    depth: 0,
    startByte: startByte,
    endByte: startByte + raw.length,
    startRow: 0,
    endRow: 0,
    raw: raw,
    content: raw,
  );
}

List<MarkdownRenderNode> _paragraphNodes(int count) {
  final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[];
  int sourceOffset = 0;
  for (int index = 0; index < count; index += 1) {
    final String raw =
        'Sliver block $index contains enough text for selection and scrolling.';
    nodes.add(_node(raw, startByte: sourceOffset));
    sourceOffset += raw.length + 2;
  }
  return nodes;
}

RenderParagraph? _richTextContaining(WidgetTester tester, String text) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    if (widget.text.toPlainText().contains(text)) {
      return element.renderObject! as RenderParagraph;
    }
  }
  return null;
}
