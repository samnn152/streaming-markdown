import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const Key _boxViewportKey = ValueKey<String>('selection-box-viewport');
const Key _sliverViewportKey = ValueKey<String>('selection-sliver-viewport');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('box selection edge-scrolls and stops without momentum', (
    WidgetTester tester,
  ) async {
    final AnimatedMarkdownSelectionController selectionController =
        AnimatedMarkdownSelectionController();
    final ScrollController scrollController = ScrollController();
    addTearDown(selectionController.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 220,
              child: ListView(
                key: _boxViewportKey,
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: <Widget>[
                  AnimatedStreamingMarkdown.fromMarkdown(
                    markdown: _longMarkdown('Box'),
                    padding: EdgeInsets.zero,
                    tokenStaggerDelay: Duration.zero,
                    tokenAnimationDuration: Duration.zero,
                    enableSelection: true,
                    selectionController: selectionController,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final _DragTrace trace = await _dragPastBottomEdge(
      tester,
      viewport: find.byKey(_boxViewportKey),
      firstLine: 'Box line 0',
      scrollController: scrollController,
    );

    expect(trace.maximumOffset, greaterThan(0));
    expect(selectionController.value.hasSelection, isTrue);
    expect(
      selectionController.value.selectedMarkdown,
      startsWith('Box line 0'),
    );
    expect(trace.secondFrameAfterRelease, closeTo(trace.releaseOffset, 0.01));

    scrollController.jumpTo(0);
    selectionController.clear();
    await tester.pump();
    final _DragTrace cancelledTrace = await _dragPastBottomEdge(
      tester,
      viewport: find.byKey(_boxViewportKey),
      firstLine: 'Box line 0',
      scrollController: scrollController,
      cancel: true,
    );
    expect(cancelledTrace.maximumOffset, greaterThan(0));
    expect(
      cancelledTrace.secondFrameAfterRelease,
      closeTo(cancelledTrace.releaseOffset, 0.01),
      reason: 'pointer cancel must stop in the same lifecycle as pointer up',
    );
  });

  testWidgets('sliver wrapper reveals, retains, and edge-scrolls selection', (
    WidgetTester tester,
  ) async {
    final AnimatedMarkdownSelectionController selectionController =
        AnimatedMarkdownSelectionController();
    final ScrollController scrollController = ScrollController();
    addTearDown(selectionController.dispose);
    addTearDown(scrollController.dispose);
    final String markdown = _longMarkdown('Sliver');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: AnimatedStreamingMarkdownSelectionArea(
              controller: selectionController,
              child: CustomScrollView(
                key: _sliverViewportKey,
                controller: scrollController,
                slivers: <Widget>[
                  AnimatedStreamingMarkdown.fromMarkdown(
                    markdown: markdown,
                    asSliver: true,
                    padding: EdgeInsets.zero,
                    tokenStaggerDelay: Duration.zero,
                    tokenAnimationDuration: Duration.zero,
                    enableSelection: true,
                    selectionController: selectionController,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    selectionController.selectAll();
    for (int frame = 0; frame < 8; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(selectionController.value.selectedMarkdown, markdown);
    expect(scrollController.offset, greaterThan(0));

    scrollController.jumpTo(0);
    await tester.pump();
    expect(selectionController.value.selectedMarkdown, markdown);

    selectionController.clear();
    await tester.pump();
    final _DragTrace trace = await _dragPastBottomEdge(
      tester,
      viewport: find.byKey(_sliverViewportKey),
      firstLine: 'Sliver line 0',
      scrollController: scrollController,
    );

    expect(trace.maximumOffset, greaterThan(0));
    expect(selectionController.value.hasSelection, isTrue);
    expect(trace.secondFrameAfterRelease, closeTo(trace.releaseOffset, 0.01));
  });

  testWidgets('touch long-press publishes a source-backed word selection', (
    WidgetTester tester,
  ) async {
    final AnimatedMarkdownSelectionController selectionController =
        AnimatedMarkdownSelectionController();
    addTearDown(selectionController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: AnimatedStreamingMarkdown.fromMarkdown(
              markdown: 'Touch selection remains source backed.',
              padding: EdgeInsets.zero,
              tokenStaggerDelay: Duration.zero,
              tokenAnimationDuration: Duration.zero,
              enableSelection: true,
              selectionController: selectionController,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph paragraph = _paragraphContaining(
      tester,
      'Touch selection',
    );
    final TestGesture gesture = await tester.startGesture(
      paragraph.localToGlobal(const Offset(54, 8)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(selectionController.value.hasSelection, isTrue);
    expect(selectionController.value.selectedMarkdown, isNotEmpty);

    // Cancelling after the assertion avoids waiting for a native selection
    // toolbar to settle on desktop integration-test hosts.
    await gesture.cancel();
    await tester.pump();
  });

  testWidgets('incomplete links transition without exposing raw Markdown', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<String> source = ValueNotifier<String>('[Hel');
    String? tappedDestination;
    addTearDown(source.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: source,
          builder: (BuildContext context, String markdown, Widget? child) {
            return AnimatedStreamingMarkdown.fromMarkdown(
              markdown: markdown,
              tokenStaggerDelay: Duration.zero,
              tokenAnimationDuration: Duration.zero,
              onLinkTap: (String destination) {
                tappedDestination = destination;
              },
            );
          },
        ),
      ),
    );
    await tester.pump();

    MarkdownInlineLink link = MarkdownSyncParser.parseMarkdown(
      source.value,
      backend: MarkdownSyncParserBackend.dart,
    ).blocks.single.inlineLinks.single;
    expect(link.label, 'Hel');
    expect(link.destination, isEmpty);
    expect(link.isCompleted, isFalse);
    expect(_paintedText(tester), isNot(contains('[Hel')));

    source.value = '[Hello](https://hello';
    await tester.pump();
    link = MarkdownSyncParser.parseMarkdown(
      source.value,
      backend: MarkdownSyncParserBackend.dart,
    ).blocks.single.inlineLinks.single;
    expect(link.label, 'Hello');
    expect(link.destination, 'https://hello');
    expect(link.isCompleted, isFalse);
    expect(_paintedText(tester), contains('https://hello'));
    expect(_paintedText(tester), isNot(contains('[Hello]')));

    final Finder destination = find.byWidgetPredicate(
      (Widget widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('https://hello'),
    );
    await tester.tap(destination);
    await tester.pump();
    expect(tappedDestination, 'https://hello');

    source.value = '[Hello](https://hello)';
    await tester.pump();
    link = MarkdownSyncParser.parseMarkdown(
      source.value,
      backend: MarkdownSyncParserBackend.dart,
    ).blocks.single.inlineLinks.single;
    expect(link.isCompleted, isTrue);
    expect(_paintedText(tester), contains('Hello'));
    expect(_paintedText(tester), isNot(contains('https://hello')));
  });

  testWidgets('custom fragments stay interactive and partially selectable', (
    WidgetTester tester,
  ) async {
    const String source = 'Interactive custom widget';
    const ValueKey<String> textKey = ValueKey<String>(
      'integration-custom-fragment',
    );
    const ValueKey<String> switchKey = ValueKey<String>(
      'integration-custom-switch',
    );
    final AnimatedMarkdownSelectionController selectionController =
        AnimatedMarkdownSelectionController();
    bool enabled = true;
    addTearDown(selectionController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 500,
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) {
                    return AnimatedStreamingMarkdown.fromMarkdown(
                      markdown: source,
                      padding: EdgeInsets.zero,
                      tokenStaggerDelay: Duration.zero,
                      tokenAnimationDuration: Duration.zero,
                      enableSelection: true,
                      selectionController: selectionController,
                      blockBuilder: (
                        BuildContext context,
                        AnimatedMarkdownBlockContext block,
                      ) {
                        return AnimatedMarkdownSelectable.fragments(
                          plainText: block.block.content,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              AnimatedMarkdownSelectionFragment(
                                plainText: block.block.content,
                                plainTextStart: 0,
                                child: Text(
                                  block.block.content,
                                  key: textKey,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                              Switch(
                                key: switchKey,
                                value: enabled,
                                onChanged: (bool value) {
                                  setState(() => enabled = value);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(switchKey));
    await tester.pump();
    expect(enabled, isFalse);

    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
      find.byKey(textKey),
    );
    final Offset start = paragraph.localToGlobal(
      paragraph.getOffsetForCaret(const TextPosition(offset: 0), Rect.zero) +
          Offset(0, paragraph.size.height / 2),
    );
    final Offset end = paragraph.localToGlobal(
      paragraph.getOffsetForCaret(const TextPosition(offset: 11), Rect.zero) +
          Offset(0, paragraph.size.height / 2),
    );
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(selectionController.value.selectedMarkdown, 'Interactive');
  });
}

Future<_DragTrace> _dragPastBottomEdge(
  WidgetTester tester, {
  required Finder viewport,
  required String firstLine,
  required ScrollController scrollController,
  bool cancel = false,
}) async {
  final RenderParagraph paragraph = _paragraphContaining(tester, firstLine);
  final Rect viewportRect = tester.getRect(viewport);
  final Offset start = paragraph.localToGlobal(const Offset(4, 8));
  final TestGesture gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(Offset(start.dx, viewportRect.bottom + 36));

  double maximumOffset = scrollController.offset;
  for (int frame = 0; frame < 30; frame += 1) {
    await tester.pump(const Duration(milliseconds: 16));
    maximumOffset = maximumOffset < scrollController.offset
        ? scrollController.offset
        : maximumOffset;
  }

  if (cancel) {
    await gesture.cancel();
  } else {
    await gesture.up();
  }
  await tester.pump(const Duration(milliseconds: 16));
  final double releaseOffset = scrollController.offset;
  await tester.pump(const Duration(milliseconds: 32));
  final double secondFrameAfterRelease = scrollController.offset;
  return _DragTrace(
    maximumOffset: maximumOffset,
    releaseOffset: releaseOffset,
    secondFrameAfterRelease: secondFrameAfterRelease,
  );
}

RenderParagraph _paragraphContaining(WidgetTester tester, String text) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText richText = element.widget as RichText;
    if (richText.text.toPlainText().contains(text)) {
      return element.renderObject! as RenderParagraph;
    }
  }
  throw StateError('No rendered paragraph contains "$text".');
}

String _longMarkdown(String prefix) {
  return <String>[
    for (int index = 0; index < 40; index += 1)
      '$prefix line $index keeps the selection moving through the viewport.',
  ].join('\n\n');
}

String _paintedText(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((RichText widget) => widget.text.toPlainText())
      .join('\n');
}

class _DragTrace {
  const _DragTrace({
    required this.maximumOffset,
    required this.releaseOffset,
    required this.secondFrameAfterRelease,
  });

  final double maximumOffset;
  final double releaseOffset;
  final double secondFrameAfterRelease;
}
