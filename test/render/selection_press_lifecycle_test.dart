import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        RenderParagraph,
        Selectable,
        SelectionEdgeUpdateEvent,
        SelectWordSelectionEvent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pointer down starts collapsed and does not highlight the line', (
    WidgetTester tester,
  ) async {
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: 'Press, then drag to begin highlighting this line.',
          enableSelection: true,
          selectionController: controller,
        ),
      ),
    );

    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final TestGesture gesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(70, 8)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    expect(controller.value.hasSelection, isFalse);
    final List<Selectable> selectables = _inlineSelectables(tester);
    for (final Selectable selectable in selectables) {
      expect(
        selectable.getSelectedContent(),
        isNull,
        reason: 'a press anchor must not temporarily select the rest of a line',
      );
    }

    // Some SelectableRegion revisions dispatch both edges on the initial
    // press before the drag recognizer has accepted any movement. Those two
    // events must still describe a collapsed caret, never a line prefix.
    final Selectable selectable = selectables.single;
    selectable.dispatchSelectionEvent(
      SelectionEdgeUpdateEvent.forStart(
        globalPosition: paragraph.localToGlobal(const Offset(0, 8)),
      ),
    );
    selectable.dispatchSelectionEvent(
      SelectionEdgeUpdateEvent.forEnd(
        globalPosition: paragraph.localToGlobal(const Offset(70, 8)),
      ),
    );
    expect(
      selectable.getSelectedContent(),
      isNull,
      reason: 'Initial framework edges must stay suppressed until movement.',
    );
    expect(controller.value.hasSelection, isFalse);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('single mouse click dismisses a finalized selection', (
    WidgetTester tester,
  ) async {
    const String source =
        'Click once inside this line to dismiss the existing selection.';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
        ),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final TestGesture selectionGesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(8, 8)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(selectionGesture.removePointer);
    await selectionGesture.moveTo(
      paragraph.localToGlobal(const Offset(125, 8)),
    );
    await tester.pump();
    await selectionGesture.up();
    await tester.pump();
    await tester.pump();
    expect(controller.value.hasSelection, isTrue);

    final List<String> transientSelections = <String>[];
    void recordNonEmptySelection() {
      if (controller.value.hasSelection) {
        transientSelections.add(controller.value.selectedMarkdown);
      }
    }

    controller.addListener(recordNonEmptySelection);
    addTearDown(() => controller.removeListener(recordNonEmptySelection));

    final TestGesture gesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(180, 8)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    expect(
      controller.value.hasSelection,
      isFalse,
      reason: 'Dismissal must happen synchronously on pointer down.',
    );
    await tester.pump();
    expect(controller.value.hasSelection, isFalse);
    expect(
      transientSelections,
      isEmpty,
      reason: 'No intermediate line-prefix selection may be published.',
    );
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(
      controller.value.hasSelection,
      isFalse,
      reason: 'A plain click must clear, not extend from a stale line anchor.',
    );
    expect(transientSelections, isEmpty);
  });

  testWidgets('external focus loss preserves a finalized selection', (
    WidgetTester tester,
  ) async {
    const String source =
        'Changing browser tabs or windows must preserve this selection.';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown: source,
            enableSelection: true,
            selectionController: controller,
          ),
        ),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final TestGesture gesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(4, 8)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(paragraph.localToGlobal(const Offset(190, 8)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    final TextSelection selection = controller.value.selection;
    final String selectedMarkdown = controller.value.selectedMarkdown;
    expect(controller.value.hasSelection, isTrue);
    expect(tester.binding.focusManager.primaryFocus, isNotNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.focusManager.primaryFocus!.unfocus();
    await tester.pump();
    await tester.pump();

    expect(controller.value.selection, selection);
    expect(controller.value.selectedMarkdown, selectedMarkdown);
    expect(controller.value.hasSelection, isTrue);
    final dynamic proxy = find
        .byWidgetPredicate(
          (Widget widget) =>
              widget.runtimeType.toString() == '_SelectableInlineTextProxy',
        )
        .evaluate()
        .single
        .renderObject!;
    expect((proxy.debugPaintSelectionRects as List<dynamic>), isNotEmpty);
  });

  testWidgets(
    'external blur immediately after pointer release preserves selection',
    (WidgetTester tester) async {
      const String source =
          'Switching tabs right after selection must preserve this snapshot.';
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedStreamingMarkdown.fromMarkdown(
              markdown: source,
              enableSelection: true,
              selectionController: controller,
            ),
          ),
        ),
      );
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText).first,
      );
      final TestGesture gesture = await tester.startGesture(
        paragraph.localToGlobal(const Offset(4, 8)),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(paragraph.localToGlobal(const Offset(210, 8)));
      await tester.pump();
      await gesture.up();

      final TextSelection selection = controller.value.selection;
      final String selectedMarkdown = controller.value.selectedMarkdown;
      expect(controller.value.hasSelection, isTrue);

      // Do not pump between pointer-up and blur. A real browser can hide the
      // page before Flutter gets another frame after the selection release.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.focusManager.primaryFocus!.unfocus();
      final SelectionArea selectionArea =
          tester.widget<SelectionArea>(find.byType(SelectionArea));
      selectionArea.onSelectionChanged?.call(null);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(controller.value.selection, selection);
      expect(controller.value.selectedMarkdown, selectedMarkdown);
      expect(controller.value.hasSelection, isTrue);
      final dynamic proxy = find
          .byWidgetPredicate(
            (Widget widget) =>
                widget.runtimeType.toString() == '_SelectableInlineTextProxy',
          )
          .evaluate()
          .single
          .renderObject!;
      expect((proxy.debugPaintSelectionRects as List<dynamic>), isNotEmpty);
    },
  );

  testWidgets('clicking another control in the same view dismisses selection', (
    WidgetTester tester,
  ) async {
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              AnimatedStreamingMarkdown.fromMarkdown(
                markdown: 'A click elsewhere in this page dismisses me.',
                enableSelection: true,
                selectionController: controller,
              ),
              const SizedBox(height: 160),
              const TextField(
                key: ValueKey<String>('outside-selection-control'),
              ),
            ],
          ),
        ),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final TestGesture gesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(4, 8)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(paragraph.localToGlobal(const Offset(150, 8)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.value.hasSelection, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('outside-selection-control')),
    );
    await tester.pump();

    expect(controller.value.hasSelection, isFalse);
  });

  testWidgets('wheel and viewport scrolling preserve finalized selection', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ScrollController scrollController = ScrollController();
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(scrollController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scrollController,
            children: <Widget>[
              AnimatedStreamingMarkdown.fromMarkdown(
                markdown: 'Scrolling must keep this finalized selection.',
                enableSelection: true,
                selectionController: controller,
              ),
              const SizedBox(height: 500),
            ],
          ),
        ),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final TestGesture gesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(4, 8)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(paragraph.localToGlobal(const Offset(155, 8)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final TextSelection selection = controller.value.selection;
    final String selectedMarkdown = controller.value.selectedMarkdown;
    expect(controller.value.hasSelection, isTrue);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: paragraph.localToGlobal(const Offset(80, 8)),
        scrollDelta: const Offset(0, 35),
      ),
    );
    await tester.pump();
    expect(scrollController.offset, greaterThan(0));
    expect(controller.value.selection, selection);
    expect(controller.value.selectedMarkdown, selectedMarkdown);

    scrollController.jumpTo(60);
    await tester.pump();
    expect(controller.value.selection, selection);
    expect(controller.value.selectedMarkdown, selectedMarkdown);
  });

  testWidgets('drag endpoint remains editable inside inter-word whitespace', (
    WidgetTester tester,
  ) async {
    const String source = 'Alpha Beta Gamma.';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
          tokenStaggerDelay: Duration.zero,
          tokenAnimationDuration: Duration.zero,
          tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
        ),
      ),
    );
    await tester.pump();

    Finder marker(String text) => find.byWidgetPredicate(
          (Widget widget) =>
              widget.runtimeType.toString() == '_MarkdownSelectableTextSpan' &&
              (widget as dynamic).text == text,
        );
    final Rect alpha = tester.getRect(marker('Alpha'));
    final Rect beta = tester.getRect(marker('Beta'));
    final Rect gamma = tester.getRect(marker('Gamma.'));
    expect(gamma.left, greaterThan(beta.right));

    final TestGesture gesture = await tester.startGesture(
      Offset(alpha.left + 0.5, alpha.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);

    await gesture.moveTo(
      Offset(beta.right + (gamma.left - beta.right) * 0.25, beta.center.dy),
    );
    await tester.pump();
    expect(controller.value.selectedMarkdown, 'Alpha Beta');

    await gesture.moveTo(
      Offset(beta.right + (gamma.left - beta.right) * 0.75, beta.center.dy),
    );
    await tester.pump();
    expect(
      controller.value.selectedMarkdown,
      'Alpha Beta ',
      reason: 'The right half of the visual gap is the caret after its space.',
    );

    await gesture.up();
    await tester.pump();

    final TestGesture reverseGesture = await tester.startGesture(
      Offset(gamma.right - 0.5, gamma.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(reverseGesture.removePointer);
    await reverseGesture.moveTo(
      Offset(beta.right + (gamma.left - beta.right) * 0.75, beta.center.dy),
    );
    await tester.pump();
    expect(
      controller.value.selectedMarkdown,
      'Gamma.',
      reason: 'A reverse drag can stop at the caret after the whitespace.',
    );

    await reverseGesture.moveTo(
      Offset(beta.right + (gamma.left - beta.right) * 0.25, beta.center.dy),
    );
    await tester.pump();
    expect(
      controller.value.selectedMarkdown,
      ' Gamma.',
      reason: 'A reverse drag can include the whitespace without jumping.',
    );

    await reverseGesture.up();
    await tester.pump();
  });

  testWidgets('double mouse click still selects a word', (
    WidgetTester tester,
  ) async {
    const String source = 'Double click keeps native word selection.';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
        ),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final Offset position = paragraph.localToGlobal(const Offset(28, 8));

    for (int i = 0; i < 2; i++) {
      final TestGesture gesture = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump();

    expect(controller.value.hasSelection, isTrue);
    expect(controller.value.selectedMarkdown, 'Double');
  });

  testWidgets('triple mouse click still selects the paragraph', (
    WidgetTester tester,
  ) async {
    const String source = 'Triple click keeps native paragraph selection.';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
        ),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final Offset position = paragraph.localToGlobal(const Offset(28, 8));

    for (int i = 0; i < 3; i++) {
      final TestGesture gesture = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump();

    expect(controller.value.hasSelection, isTrue);
    expect(controller.value.selectedMarkdown, source);
  });

  testWidgets('the first edge update never selects to the line boundary', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: 'A single edge is only an anchor, not a range.',
          enableSelection: true,
        ),
      ),
    );

    final Selectable selectable = _inlineSelectables(tester).single;
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    selectable.dispatchSelectionEvent(
      SelectionEdgeUpdateEvent.forStart(
        globalPosition: paragraph.localToGlobal(const Offset(70, 8)),
      ),
    );

    expect(selectable.getSelectedContent(), isNull);
  });

  testWidgets('select-word inside a finalized range preserves that range', (
    WidgetTester tester,
  ) async {
    const String source = 'Keep this existing selection while holding.';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
        ),
      ),
    );
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 28);
    await tester.pump();

    final Selectable selected = _inlineSelectables(tester).singleWhere(
      (Selectable selectable) =>
          selectable.getSelectedContent()?.plainText == source.substring(0, 28),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    selected.dispatchSelectionEvent(
      SelectWordSelectionEvent(
        globalPosition: paragraph.localToGlobal(const Offset(75, 8)),
      ),
    );

    expect(selected.getSelectedContent()?.plainText, source.substring(0, 28));
  });
}

List<Selectable> _inlineSelectables(WidgetTester tester) {
  return find
      .byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_SelectableInlineTextProxy',
      )
      .evaluate()
      .map((Element element) => element.renderObject)
      .whereType<Selectable>()
      .toList(growable: false);
}
