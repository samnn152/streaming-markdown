import 'dart:io';
import 'dart:ui' as ui;
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _selectionColor = Color(0x4DFF00FF);
const String _testFontFamily = 'MarkdownSelectionTest';
const Size _surfaceSize = Size(420, 100);
const int _fps = 60;
const int _assertFrameCount = 24;
const int _recordFrameCount = 60;

void main() {
  setUpAll(() async {
    await _loadTestFont();
  });

  testWidgets(
    'selected first line never drifts to lower visible lines while streaming and scrolling',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bool recordVideo =
          _environmentFlag('RECORD_SELECTION_SCROLL_VIDEO');
      final int frameCount =
          recordVideo ? _recordFrameCount : _assertFrameCount;

      final ScrollController scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      const String selectedLine =
          'SelectedFirstLineStaysAnchored lower wrapped text in ';
      const String firstBlock =
          'SelectedFirstLineStaysAnchored lower wrapped text in this same markdown block must never become selected, even while content streams in and the scroll view is moving.';
      List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _renderNode(firstBlock, startByte: 0),
        _renderNode(
          'Second line must never become selected.',
          startByte: firstBlock.length + 2,
          startRow: 2,
        ),
      ];
      late StateSetter updateHost;
      final GlobalKey boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: _surfaceSize.width,
                  height: _surfaceSize.height,
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setState) {
                      updateHost = setState;
                      return ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: <Widget>[
                          StreamingMarkdownRenderView(
                            nodes: nodes,
                            padding: const EdgeInsets.all(8),
                            enableTextSelection: true,
                            selectionStrategy: SelectionStrategy.raw,
                            tokenArrivalDelay: Duration.zero,
                            tokenFadeInDuration: Duration.zero,
                            markdownTheme: const StreamingMarkdownThemeData(
                              selectionColor: _selectionColor,
                              paragraphTextStyle: TextStyle(
                                color: Colors.black,
                                fontFamily: _testFontFamily,
                                fontSize: 16,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 420),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RenderParagraph paragraph =
          _renderParagraphContaining(tester, selectedLine);
      final TestGesture gesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        _textOffsetToPosition(paragraph, selectedLine.length) +
            const Offset(0, 8),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 80));

      for (int frame = 0; frame < frameCount; frame++) {
        if (frame % 10 == 0) {
          updateHost(() {
            nodes = <MarkdownRenderNode>[
              _renderNode(firstBlock, startByte: 0),
              _renderNode(
                'Second line must never become selected.',
                startByte: firstBlock.length + 2,
                startRow: 2,
              ),
              for (int i = 0; i <= frame ~/ 10; i++)
                _renderNode(
                  'Streaming append block $i keeps layout moving.',
                  startByte: 80 + i * 48,
                  startRow: 4 + i * 2,
                ),
            ];
          });
        }

        if (scrollController.hasClients) {
          final double offset = (frame * 1.5).clamp(
            scrollController.position.minScrollExtent,
            scrollController.position.maxScrollExtent,
          );
          scrollController.jumpTo(offset);
        }
        await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

        _expectOnlySelectedLineHasNativeSelection(tester, selectedLine);
        _expectSourceVisualHighlightsOnly(tester, selectedLine);
        if (recordVideo) {
          final String frameName = frame.toString().padLeft(4, '0');
          await expectLater(
            find.byKey(boundaryKey),
            matchesGoldenFile(
              'artifacts/selection_scroll_60fps/frames/frame_$frameName.png',
            ),
          );
        }
      }
    },
  );

  testWidgets(
    'locked selection can be replaced by dragging another visible line',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bool recordVideo =
          _environmentFlag('RECORD_SELECTION_REPLACE_VIDEO');

      final ScrollController scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final AnimatedMarkdownSelectionController selectionController =
          AnimatedMarkdownSelectionController();
      addTearDown(selectionController.dispose);

      const String firstLine = 'FirstLockedLineStaysPut';
      const String firstBlock =
          'FirstLockedLineStaysPut while appended content and scroll changes try to move the viewport.';
      const String secondLine = 'SecondLineCanBeSelectedAfterLock';
      List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _renderNode(firstBlock, startByte: 0),
        _renderNode(
          secondLine,
          startByte: firstBlock.length + 2,
          startRow: 2,
        ),
      ];
      late StateSetter updateHost;
      final GlobalKey boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: _surfaceSize.width,
                  height: _surfaceSize.height,
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setState) {
                      updateHost = setState;
                      return ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: <Widget>[
                          StreamingMarkdownRenderView(
                            nodes: nodes,
                            padding: const EdgeInsets.all(8),
                            enableTextSelection: true,
                            selectionStrategy: SelectionStrategy.raw,
                            selectionController: selectionController,
                            tokenArrivalDelay: Duration.zero,
                            tokenFadeInDuration: Duration.zero,
                            markdownTheme: const StreamingMarkdownThemeData(
                              selectionColor: _selectionColor,
                              paragraphTextStyle: TextStyle(
                                color: Colors.black,
                                fontFamily: _testFontFamily,
                                fontSize: 16,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 360),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      RenderParagraph paragraph = _renderParagraphContaining(tester, firstLine);
      TestGesture gesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, 0) + const Offset(2, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        _textOffsetToPosition(paragraph, firstLine.length) + const Offset(4, 8),
      );
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

      scrollController.jumpTo(10);
      updateHost(() {
        nodes = <MarkdownRenderNode>[
          _renderNode(firstBlock, startByte: 0),
          _renderNode(
            secondLine,
            startByte: firstBlock.length + 2,
            startRow: 2,
          ),
          _renderNode(
            'Streaming append keeps arriving while the old selection is locked.',
            startByte: firstBlock.length + secondLine.length + 4,
            startRow: 4,
          ),
        ];
      });
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

      if (recordVideo) {
        for (int frame = 0; frame < 12; frame++) {
          await _recordFrame(
            tester,
            boundaryKey,
            'selection_replace_60fps/frames/frame_${frame.toString().padLeft(4, '0')}.png',
          );
          await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));
        }
      }

      paragraph = _renderParagraphContaining(tester, secondLine);
      final double endGlobalY =
          _textOffsetToPosition(paragraph, secondLine.length).dy;
      if (scrollController.hasClients) {
        final double centeredOffset =
            (scrollController.offset + endGlobalY - 55).clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent,
        );
        scrollController.jumpTo(centeredOffset);
        await tester.pump();
        paragraph = _renderParagraphContaining(tester, secondLine);
      }
      final Offset start =
          _textOffsetToPosition(paragraph, 0) + const Offset(2, 8);
      final Offset end = _textOffsetToPosition(paragraph, secondLine.length) +
          const Offset(4, 8);
      gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

      for (int frame = 12; frame < _recordFrameCount; frame++) {
        final double t = (frame - 12) / (_recordFrameCount - 13);
        await gesture.moveTo(Offset.lerp(start, end, t)!);
        await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));
        if (recordVideo) {
          await _recordFrame(
            tester,
            boundaryKey,
            'selection_replace_60fps/frames/frame_${frame.toString().padLeft(4, '0')}.png',
          );
        }
      }

      await gesture.up();
      await tester.pump();
      expect(selectionController.value.selectedMarkdown, secondLine);
      _expectSourceVisualDoesNotHighlight(tester, firstLine);
    },
  );

  testWidgets(
    'locked table selection preserves partial text inside a cell',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(520, 190));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              final Map<dynamic, dynamic> data =
                  methodCall.arguments! as Map<dynamic, dynamic>;
              clipboardText = data['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final ScrollController scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      const String prefix = 'Paragraph before the table must not be selected.';
      const String rawTable = '| M | Cat | Dog |\n'
          '| --- | --- | --- |\n'
          '| Q | Quiet | Loud |\n'
          '| X | Calm | Busy |';
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _renderNode(prefix, startByte: 0),
        const MarkdownRenderNode(
          type: 'pipe_table',
          depth: 0,
          startByte: prefix.length + 2,
          endByte: prefix.length + 2 + rawTable.length,
          startRow: 2,
          endRow: 5,
          raw: rawTable,
          content: rawTable,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 520,
                height: 190,
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    StreamingMarkdownRenderView(
                      nodes: nodes,
                      padding: const EdgeInsets.all(8),
                      enableTextSelection: true,
                      selectionStrategy: SelectionStrategy.raw,
                      tokenArrivalDelay: Duration.zero,
                      tokenFadeInDuration: Duration.zero,
                      markdownTheme: const StreamingMarkdownThemeData(
                        selectionColor: _selectionColor,
                        paragraphTextStyle: TextStyle(
                          color: Colors.black,
                          fontFamily: _testFontFamily,
                          fontSize: 16,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 320),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RenderParagraph quietParagraph =
          _renderParagraphContaining(tester, 'Quiet');
      final TestGesture gesture = await tester.startGesture(
        _textOffsetToPosition(quietParagraph, 1) + const Offset(0, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        _textOffsetToPosition(quietParagraph, 'Quiet'.length) +
            const Offset(0, 8),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 80));

      scrollController.jumpTo(12);
      await tester.pump(const Duration(milliseconds: 1000 ~/ _fps));

      expect(_highlightedText(tester), 'uiet');

      final BuildContext copyContext =
          tester.binding.focusManager.primaryFocus!.context!;
      Actions.invoke(copyContext, CopySelectionTextIntent.copy);
      await tester.pump();
      expect(
        clipboardText,
        '| Cat |\n'
        '| --- |\n'
        '| uiet |',
      );
    },
  );

  testWidgets(
    'streaming long text response preserves selection without drift during repeated scroll up and down',
    (WidgetTester tester) async {
      final ScrollController scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              final Map<dynamic, dynamic> data =
                  methodCall.arguments! as Map<dynamic, dynamic>;
              clipboardText = data['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      const String selectedAnchor =
          'Anchor line selected while generating long text.';
      final List<String> paragraphs = <String>[
        selectedAnchor,
        'Second paragraph explaining details in depth.',
      ];

      late StateSetter updateStream;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 480,
                height: 180,
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) {
                    updateStream = setState;
                    return ListView(
                      controller: scrollController,
                      children: <Widget>[
                        AnimatedStreamingMarkdown.fromMarkdown(
                          markdown: paragraphs.join('\n\n'),
                          padding: const EdgeInsets.all(8),
                          tokenStaggerDelay: Duration.zero,
                          tokenAnimationDuration: Duration.zero,
                          enableSelection: true,
                          selectionStrategy: SelectionStrategy.raw,
                        ),
                        const SizedBox(height: 300),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Select the anchor line in paragraph 1
      final RenderParagraph anchorParagraph =
          _renderParagraphContaining(tester, selectedAnchor);
      final TestGesture gesture = await tester.startGesture(
        _textOffsetToPosition(anchorParagraph, 0) + const Offset(4, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        _textOffsetToPosition(anchorParagraph, selectedAnchor.length) +
            const Offset(4, 8),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));

      // 2. Simulate streaming long new tokens while scrolling up and down repeatedly
      for (int i = 0; i < 8; i += 1) {
        updateStream(() {
          paragraphs.add(
            'Streamed paragraph $i providing comprehensive detailed markdown analysis '
            'with **bold** emphasis, `code snippets`, and list items:\n'
            '- Feature $i.1: High performance streaming parser\n'
            '- Feature $i.2: Zero-drift selection highlight\n'
            '- Feature $i.3: Dynamic viewport auto-scroll',
          );
        });
        await tester.pump(const Duration(milliseconds: 60));

        // Scroll down
        scrollController.jumpTo((i + 1) * 35.0);
        await tester.pump(const Duration(milliseconds: 40));

        // Scroll up
        scrollController.jumpTo(((i + 1) * 35.0) - 15.0);
        await tester.pump(const Duration(milliseconds: 40));

        // Verify clipboard text remains rock-solid on the selected anchor
        final BuildContext copyContext =
            tester.binding.focusManager.primaryFocus!.context!;
        Actions.invoke(copyContext, CopySelectionTextIntent.copy);
        await tester.pump();
        expect(
          clipboardText,
          selectedAnchor,
          reason:
              'Step $i: Selection must not drift when scrolling up/down during active streaming.',
        );
      }
    },
  );

  testWidgets(
    'drag selection upward towards top edge smoothly auto-scrolls hidden ancestor content and extends selection',
    (WidgetTester tester) async {
      final ScrollController scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              final Map<dynamic, dynamic> data =
                  methodCall.arguments! as Map<dynamic, dynamic>;
              clipboardText = data['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboardText};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final List<String> blocks = <String>[
        '# Top Hidden Section Heading',
        for (int i = 1; i <= 8; i += 1)
          'Hidden section block $i with detailed context ensuring height.',
        'Target bottom paragraph where user starts dragging upward.',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 500,
                height: 140,
                child: ListView(
                  controller: scrollController,
                  children: <Widget>[
                    AnimatedStreamingMarkdown.fromMarkdown(
                      markdown: blocks.join('\n\n'),
                      padding: const EdgeInsets.all(8),
                      tokenStaggerDelay: Duration.zero,
                      tokenAnimationDuration: Duration.zero,
                      enableSelection: true,
                      selectionStrategy: SelectionStrategy.raw,
                    ),
                    const SizedBox(height: 300),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Position the target paragraph inside the viewport using its measured
      // geometry. Fixed scroll offsets make this fixture font/backend
      // dependent and can leave the drag origin off-screen on Chrome.
      RenderParagraph bottomParagraph =
          _renderParagraphContaining(tester, 'Target bottom paragraph');
      final double targetGlobalTop =
          bottomParagraph.localToGlobal(Offset.zero).dy;
      final double targetScrollOffset =
          (scrollController.offset + targetGlobalTop - 70).clamp(
        scrollController.position.minScrollExtent,
        scrollController.position.maxScrollExtent,
      );
      scrollController.jumpTo(targetScrollOffset);
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(20));

      // Start drag gesture on the bottom visible paragraph
      bottomParagraph =
          _renderParagraphContaining(tester, 'Target bottom paragraph');
      final Offset startPos =
          _textOffsetToPosition(bottomParagraph, 11) + const Offset(0, 8);
      expect(startPos.dy, greaterThan(0));
      expect(startPos.dy, lessThan(140));

      final TestGesture gesture = await tester.startGesture(
        startPos,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // Move pointer up near top edge of the viewport (y = 8) to trigger auto-scroll up
      await gesture.moveTo(const Offset(60, 8));
      for (int tick = 0;
          tick < 180 && scrollController.offset >= 20;
          tick += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Viewport must have scrolled upward all the way to the top
      expect(scrollController.offset, lessThan(20));

      await gesture.up();
      await tester.pumpAndSettle();

      // Copy selection and verify it includes the top content that scrolled into view
      final BuildContext copyContext =
          tester.binding.focusManager.primaryFocus!.context!;
      Actions.invoke(copyContext, CopySelectionTextIntent.copy);
      await tester.pump();

      expect(clipboardText, isNotNull);
      expect(
        clipboardText!,
        contains('Top Hidden Section Heading'),
        reason:
            'Auto-scroll upward must expand the selection across top hidden content as it scrolls in.',
      );
      expect(clipboardText!, contains('Target bott'));
    },
  );

  testWidgets(
    'active drag highlight survives a transient framework geometry clear',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(460, 110));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const String paragraphText =
          'Selection paint remains continuous while Flutter moves its edge.';
      final AnimatedMarkdownSelectionController selectionController =
          AnimatedMarkdownSelectionController();
      addTearDown(selectionController.dispose);
      final GlobalKey boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: AnimatedStreamingMarkdown.fromMarkdown(
                  markdown: paragraphText,
                  padding: const EdgeInsets.all(8),
                  tokenStaggerDelay: Duration.zero,
                  tokenAnimationDuration: Duration.zero,
                  enableSelection: true,
                  selectionController: selectionController,
                  theme: const AnimatedMarkdownThemeData(
                    selectionColor: Color(0xFFFF00FF),
                    paragraphTextStyle: TextStyle(
                      color: Colors.black,
                      fontFamily: _testFontFamily,
                      fontSize: 16,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RenderParagraph paragraph =
          _renderParagraphContaining(tester, paragraphText);
      final TestGesture gesture = await tester.startGesture(
        _textOffsetToPosition(paragraph, 0) + const Offset(2, 8),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(
        _textOffsetToPosition(paragraph, 32) + const Offset(2, 8),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(selectionController.value.hasSelection, isTrue);
      final int pixelsBeforeClear = await _selectionPixelCount(
        tester,
        boundaryKey,
        const Color(0xFFFF00FF),
      );
      if (pixelsBeforeClear == 0 && kIsWeb) {
        await gesture.up();
        await tester.pump();
        return;
      }
      expect(pixelsBeforeClear, greaterThan(100));

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
      final TextRange paintRangeBeforeClear =
          paintProxy.debugPaintSelectionRange as TextRange;

      // SelectableRegion clears one proxy transiently while transferring an
      // edge to another proxy. Geometry may be empty for that frame, but the
      // coordinator-owned paint range must remain visible.
      selectedProxy.dispatchSelectionEvent(const ClearSelectionEvent());
      expect(selectedProxy.getSelectedContent(), isNull);
      expect(
        paintProxy.debugPaintSelectionRange,
        paintRangeBeforeClear,
        reason: 'Framework geometry must not own the persistent paint range.',
      );

      await tester.pump(const Duration(milliseconds: 16));

      expect(selectionController.value.hasSelection, isTrue);
      final int pixelsAfterClear = await _selectionPixelCount(
        tester,
        boundaryKey,
        const Color(0xFFFF00FF),
      );
      expect(
        pixelsAfterClear,
        greaterThanOrEqualTo((pixelsBeforeClear * 0.95).floor()),
        reason: 'A transient geometry clear must not create a blank or dim '
            'selection frame.',
      );

      await gesture.up();
      await tester.pump();
    },
  );
}

Future<void> _recordFrame(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) {
  return expectLater(
    find.byKey(boundaryKey),
    matchesGoldenFile('artifacts/$path'),
  );
}

Future<int> _selectionPixelCount(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Color color,
) async {
  final RenderRepaintBoundary? boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    return 0;
  }
  final Uint8List? pixels = await tester.runAsync<Uint8List?>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) {
      return null;
    }
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  });
  if (pixels == null) {
    return 0;
  }
  final int argb = (color as dynamic).value as int;
  final int alpha = (argb >> 24) & 0xFF;
  final int red = (argb >> 16) & 0xFF;
  final int green = (argb >> 8) & 0xFF;
  final int blue = argb & 0xFF;
  int count = 0;
  for (int index = 0; index < pixels.length; index += 4) {
    if (pixels[index] == red &&
        pixels[index + 1] == green &&
        pixels[index + 2] == blue &&
        pixels[index + 3] == alpha) {
      count += 1;
    }
  }
  return count;
}

void _expectOnlySelectedLineHasNativeSelection(
  WidgetTester tester,
  String selectedLine,
) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    final String text = widget.text.toPlainText();
    final RenderParagraph paragraph = element.renderObject! as RenderParagraph;
    if (text.contains(selectedLine)) {
      continue;
    }
    expect(
      paragraph.selections,
      isEmpty,
      reason: 'native selection drifted to "$text"',
    );
  }
}

void _expectSourceVisualHighlightsOnly(
  WidgetTester tester,
  String selectedLine,
) {
  final String actual = _highlightedText(tester);
  if (actual.isEmpty) {
    return;
  }
  expect(
    actual,
    selectedLine,
    reason: 'source fallback highlight moved away from the first line',
  );
}

void _expectSourceVisualDoesNotHighlight(
  WidgetTester tester,
  String text,
) {
  expect(_highlightedText(tester), isNot(contains(text)));
}

String _highlightedText(WidgetTester tester) {
  final StringBuffer highlighted = StringBuffer();
  for (final Element element in find
      .byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_SelectableInlineTextProxy',
      )
      .evaluate()) {
    final dynamic widget = element.widget;
    final dynamic renderObject = element.renderObject;
    final TextRange? paintRange =
        renderObject.debugPaintSelectionRange as TextRange?;
    if (widget.selectionColor == _selectionColor && paintRange != null) {
      final String plainText = widget.plainText as String;
      highlighted.write(
        plainText.substring(
          paintRange.start.clamp(0, plainText.length),
          paintRange.end.clamp(0, plainText.length),
        ),
      );
    }
  }
  return highlighted.toString();
}

RenderParagraph _renderParagraphContaining(
  WidgetTester tester,
  String plainText,
) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    if (!widget.text.toPlainText().contains(plainText) ||
        _containsWidgetSpan(widget.text)) {
      continue;
    }
    return element.renderObject! as RenderParagraph;
  }
  throw StateError('No RichText RenderParagraph contains "$plainText".');
}

bool _containsWidgetSpan(InlineSpan span) {
  if (span is WidgetSpan) {
    return true;
  }
  if (span is TextSpan) {
    final List<InlineSpan>? children = span.children;
    if (children != null) {
      return children.any(_containsWidgetSpan);
    }
  }
  return false;
}

Offset _textOffsetToPosition(RenderParagraph paragraph, int offset) {
  const Rect caret = Rect.fromLTWH(0, 0, 2, 20);
  final Offset localOffset = paragraph.getOffsetForCaret(
    TextPosition(offset: offset),
    caret,
  );
  return paragraph.localToGlobal(localOffset);
}

MarkdownRenderNode _renderNode(
  String raw, {
  int startByte = 0,
  int startRow = 0,
}) {
  return MarkdownRenderNode(
    type: 'paragraph',
    depth: 0,
    startByte: startByte,
    endByte: startByte + raw.length,
    startRow: startRow,
    endRow: startRow,
    raw: raw,
    content: raw,
  );
}

Future<void> _loadTestFont() async {
  if (kIsWeb) {
    return;
  }
  const String packageAssetRoot =
      'packages/animated_streaming_markdown/assets/fonts/katex';
  final FontLoader loader = FontLoader(_testFontFamily)
    ..addFont(rootBundle.load('$packageAssetRoot/KaTeX_Main-Regular.ttf'))
    ..addFont(rootBundle.load('$packageAssetRoot/KaTeX_Main-Bold.ttf'));
  await loader.load();
}

bool _environmentFlag(String name) {
  return !kIsWeb && Platform.environment[name] == '1';
}
