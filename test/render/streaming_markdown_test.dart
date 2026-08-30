import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:animated_streaming_markdown/src/third_party/flutter_math/flutter_math.dart';

void main() {
  test('library name is stable', () {
    expect(streamingMarkdownLibraryName, 'animated_streaming_markdown');
  });

  test('native parser availability can be required by release CI', () {
    final bool requireNative =
        Platform.environment['REQUIRE_STREAMING_MARKDOWN_NATIVE'] == 'true';
    if (!requireNative && !isStreamingMarkdownNativeLibraryAvailable) {
      return;
    }

    expect(isStreamingMarkdownNativeLibraryAvailable, isTrue);
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '# Native check\n\n```dart\nprint(1);\n```',
      backend: MarkdownSyncParserBackend.native,
    );

    expect(result.nativeAvailable, isTrue);
    expect(result.blocks.map((MarkdownRenderNode node) => node.type), <String>[
      'atx_heading',
      'paragraph',
      'fenced_code_block',
    ]);
  });

  test('rope string append, random access and substring', () {
    final RopeString rope = RopeString();
    rope.append('Hello');
    rope.append(', ');
    rope.append('streaming');
    rope.append(' markdown');

    expect(rope.length, 25);
    expect(rope.charAt(1), 'e');
    expect(rope.substring(0, 5), 'Hello');
    expect(rope.substring(7, 16), 'streaming');
    expect(rope.substring(17), 'markdown');
    expect(rope.toString(), 'Hello, streaming markdown');
  });

  test('parser returns markdown blocks from rope', () {
    final RopeString rope = RopeString();
    rope.append('# Title\n');
    rope.append('\n');
    rope.append('Paragraph line 1\nParagraph line 2\n');
    rope.append('\n- one\n- two\n');
    rope.append('```dart\nfinal x = 1;\n```\n');

    final MarkdownDocument doc = const RopeMarkdownParser().parse(rope);

    expect(doc.blocks.length, 4);

    final HeadingNode heading = doc.blocks[0] as HeadingNode;
    expect(heading.level, 1);
    expect(heading.text, 'Title');

    final ParagraphNode paragraph = doc.blocks[1] as ParagraphNode;
    expect(paragraph.text, 'Paragraph line 1\nParagraph line 2');

    final ListNode list = doc.blocks[2] as ListNode;
    expect(list.ordered, false);
    expect(list.items.map((item) => item.text).toList(), <String>[
      'one',
      'two',
    ]);

    final CodeFenceNode fence = doc.blocks[3] as CodeFenceNode;
    expect(fence.language, 'dart');
    expect(fence.code, 'final x = 1;\n');
    expect(fence.closed, true);
  });

  test('streaming parser append and reparse', () {
    final StreamingMarkdownParser parser = StreamingMarkdownParser();

    MarkdownDocument doc = parser.appendAndParse('# Header\n');
    expect(doc.blocks.length, 1);
    expect((doc.blocks.first as HeadingNode).text, 'Header');

    doc = parser.appendAndParse('\nBody\n');
    expect(doc.blocks.length, 2);
    expect((doc.blocks[1] as ParagraphNode).text, 'Body');
  });

  test('sync parser returns render blocks without isolate startup', () {
    final Stopwatch watch = Stopwatch()..start();
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      '# Sync title\n\nShort markdown renders immediately.',
      backend: MarkdownSyncParserBackend.dart,
    );
    watch.stop();

    expect(result.blocks, hasLength(2));
    expect(result.mode, 'sync-dart-set');
    expect(result.blocks.first.type, anyOf('atx_heading', 'setext_heading'));
    expect(result.blocks.first.content, 'Sync title');
    debugPrint(
      'MarkdownSyncParser dart parse: '
      '${watch.elapsedMicroseconds / 1000} ms',
    );
    expect(watch.elapsedMilliseconds, lessThan(50));
  });

  test('sync Dart parser emits renderer-compatible block types', () {
    const String markdown = '''
---
title: Demo
---

Setext title
===

> quoted
> text

| Name | Status |
| --- | --- |
| Dart | Ready |

---

<div>HTML</div>

[^note]: footnote text

[ref]: https://example.com
''';

    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      markdown,
      backend: MarkdownSyncParserBackend.dart,
    );
    final List<String> types = result.blocks
        .map((MarkdownRenderNode block) => block.type)
        .toList(growable: false);

    expect(types, contains('front_matter'));
    expect(types, contains('setext_heading'));
    expect(types, contains('block_quote'));
    expect(types, contains('pipe_table'));
    expect(types, contains('thematic_break'));
    expect(types, contains('html_block'));
    expect(types, contains('footnote_definition'));
    expect(types, contains('link_reference_definition'));
    expect(
      result.blocks
          .firstWhere(
            (MarkdownRenderNode block) => block.type == 'pipe_table',
          )
          .raw,
      contains('| Dart | Ready |'),
    );
  });

  test('sync Dart parser content matches GFM block golden', () {
    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      _gfmParserGoldenMarkdown,
      backend: MarkdownSyncParserBackend.dart,
    );

    expect(_nodeContentGolden(result.blocks), <String>[
      'atx_heading|content=GFM parser case 1|raw=# GFM parser case 1',
      'paragraph|content=Streaming markdown case 1 mixes **strong**, _emphasis_, ~~deleted text~~, `inline | code`, an autolink https://example.com/1, and a reference link to [the docs][docs].|raw=Streaming markdown case 1 mixes **strong**, _emphasis_, ~~deleted text~~, `inline | code`, an autolink https://example.com/1, and a reference link to [the docs][docs].',
      'block_quote|content=GFM quote content keeps **inline markdown** intact.|raw=> GFM quote content keeps **inline markdown** intact.',
      'list|content=[x] completed task for case 1 [ ] pending task with `inline | pipe` nested content continues after the task marker|raw=- [x] completed task for case 1 - [ ] pending task with `inline | pipe` - nested content continues after the task marker',
      'pipe_table|content=| Feature | Value | Notes | | --- | ---: | --- | | Case | 1 | table row | | Pipes | `a | b` | inline code cell ||raw=| Feature | Value | Notes | | --- | ---: | --- | | Case | 1 | table row | | Pipes | `a | b` | inline code cell |',
      'paragraph|content=Footnote reference[^case-1] before the code fence.|raw=Footnote reference[^case-1] before the code fence.',
      "fenced_code_block|content=final value1 = 17; debugPrint('case 1: \$value1');|raw=```dart final value1 = 17; debugPrint('case 1: \$value1'); ```",
      'footnote_definition|content=Footnote body for parser case 1.|raw=[^case-1]: Footnote body for parser case 1.',
      'link_reference_definition|content=https://pub.dev/packages/animated_streaming_markdown|raw=[docs]: https://pub.dev/packages/animated_streaming_markdown',
    ]);
  });

  test('native parser exposes content for render block containers', () {
    if (!isStreamingMarkdownNativeLibraryAvailable) {
      return;
    }

    final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
      _gfmParserGoldenMarkdown,
      backend: MarkdownSyncParserBackend.native,
    );

    for (final String type in <String>[
      'block_quote',
      'list',
      'fenced_code_block',
      'footnote_definition',
      'link_reference_definition',
    ]) {
      final MarkdownRenderNode node = result.blocks.firstWhere(
        (MarkdownRenderNode node) => node.type == type,
      );
      expect(
        _compactGoldenText(node.content),
        isNotEmpty,
        reason: '$type should expose meaningful content',
      );
    }
  });

  test('parser warm-up is shared by sync and worker APIs', () async {
    final StreamingMarkdownWarmUpResult result =
        await warmUpStreamingMarkdownParser(includeWorker: true);

    expect(result.totalTime, greaterThanOrEqualTo(Duration.zero));
    expect(result.currentIsolateTime, greaterThanOrEqualTo(Duration.zero));
    expect(result.workerTime, isNotNull);
  });

  test('tree-sitter block parser returns full syntax tree', () {
    if (!isStreamingMarkdownNativeLibraryAvailable) {
      return;
    }
    const TreeSitterMarkdownParser parser = TreeSitterMarkdownParser();
    final MarkdownSyntaxNode root = parser.parseBlocks(
      '# Title\n\n- one\n- two\n\n```dart\nprint(1)\n```\n',
    );

    expect(root.type, 'document');
    final Set<String> types = _collectTypes(root);
    expect(types.contains('atx_heading'), isTrue);
    expect(types.contains('list'), isTrue);
    expect(types.contains('fenced_code_block'), isTrue);
  });

  test('tree-sitter inline parser returns inline nodes', () {
    if (!isStreamingMarkdownNativeLibraryAvailable) {
      return;
    }
    const TreeSitterMarkdownParser parser = TreeSitterMarkdownParser();
    final MarkdownSyntaxNode root = parser.parseInlines(
      'this is **bold** and *italic* with [link](https://example.com)',
    );

    final Set<String> types = _collectTypes(root);
    expect(types.contains('strong_emphasis'), isTrue);
    expect(types.contains('emphasis'), isTrue);
    expect(types.contains('inline_link'), isTrue);
  });

  test('parse worker keeps table delimiter rows for markdown copy', () async {
    final StreamingMarkdownParseWorker worker = StreamingMarkdownParseWorker();
    await worker.start();
    try {
      final StreamingMarkdownParseResult result = await worker.request(
        op: 'set',
        text: '| A | B |\n| --- | --- |\n| C | D |',
        includeNodes: true,
      );
      if (!result.nativeAvailable) {
        return;
      }

      expect(
        result.renderNodes.map((MarkdownRenderNode node) => node.type),
        contains('pipe_table_delimiter_row'),
      );
    } finally {
      worker.dispose();
    }
  });

  testWidgets('fromMarkdown with zero durations paints on first pump', (
    WidgetTester tester,
  ) async {
    final Stopwatch watch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown: '# Instant\n\nShort markdown should show now.',
            padding: EdgeInsets.zero,
            tokenStaggerDelay: Duration.zero,
            tokenAnimationDuration: Duration.zero,
          ),
        ),
      ),
    );
    watch.stop();

    expect(find.text('Instant'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('markdown'), findsOneWidget);
    expect(find.text('now.'), findsOneWidget);
    debugPrint(
      'fromMarkdown zero-duration first pump: '
      '${watch.elapsedMicroseconds / 1000} ms',
    );
    expect(watch.elapsedMilliseconds, lessThan(500));
  });

  testWidgets('code block copy button copies code text when enabled', (
    WidgetTester tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['text'] as String?;
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown: '```dart\nfinal answer = 42;\n```',
            tokenStaggerDelay: Duration.zero,
            tokenAnimationDuration: Duration.zero,
            showCodeBlockCopyButton: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Copy code'));
    await tester.pump();

    expect(clipboardText, 'final answer = 42;');
  });

  testWidgets(
      'markdown text uses text cursor and copy button uses click cursor',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Cursor target text.'),
              _renderNode(
                '```dart\nfinal answer = 42;\n```',
                type: 'fenced_code_block',
                startByte: 21,
                startRow: 2,
              ),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            showCodeBlockCopyButton: true,
            tokenArrivalDelay: Duration.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.ancestor(
        of: find.byWidgetPredicate(
          (Widget widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('Cursor target text.'),
        ),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is MouseRegion && widget.cursor == SystemMouseCursors.text,
        ),
      ),
      findsOneWidget,
    );

    expect(
      find.ancestor(
        of: find.byTooltip('Copy code'),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('rendered links are tappable with text selection enabled', (
    WidgetTester tester,
  ) async {
    String? tappedUrl;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Tap [OpenAI](https://openai.com) for details.'),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            onLinkTap: (String url) {
              tappedUrl = url;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('OpenAI'));
    await tester.pump();

    expect(tappedUrl, 'https://openai.com');
  });

  testWidgets('selection-enabled inline text avoids token widget layout drift',
      (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[
                _renderNode(
                  'Inline links render as tappable spans: '
                  '[OpenAI](https://openai.com).',
                ),
                _renderNode(
                  'Autolinks render from angle brackets: '
                  '<https://github.com>.',
                  startByte: 76,
                  startRow: 2,
                ),
              ],
              padding: EdgeInsets.zero,
              enableTextSelection: true,
              tokenFadeInDuration: const Duration(milliseconds: 200),
              tokenArrivalDelay: const Duration(milliseconds: 20),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));

    expect(_inlineSelectionProxyCount(tester), 2);
    expect(find.text('OpenAI'), findsOneWidget);
  });

  testWidgets('selection-enabled inline text still fades in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Inline [OpenAI](https://openai.com) link.'),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            tokenArrivalDelay: Duration.zero,
            tokenFadeInDuration: const Duration(milliseconds: 200),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(_activeTokenOpacity(tester), greaterThan(0));
    expect(_activeTokenOpacity(tester), lessThan(1));
    expect(_inlineSelectionProxyCount(tester), 1);
    expect(_totalWidgetSpanCount(tester), greaterThan(0));
  });

  testWidgets('selection keeps animated inline pixels identical', (
    WidgetTester tester,
  ) async {
    const Size surfaceSize = Size(460, 96);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final MarkdownRenderNode node = _renderNode(
      'Pixel [OpenAI](https://openai.com) **bold** words stay exact.',
    );

    Future<Uint8List> capture({required bool enableTextSelection}) async {
      final Key boundaryKey = ValueKey<String>(
        'selection-animation-pixel-${enableTextSelection ? 'on' : 'off'}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: surfaceSize.width,
                  height: surfaceSize.height,
                  child: StreamingMarkdownRenderView(
                    nodes: <MarkdownRenderNode>[node],
                    padding: const EdgeInsets.all(8),
                    enableTextSelection: enableTextSelection,
                    tokenArrivalDelay: Duration.zero,
                    tokenFadeInDuration: const Duration(milliseconds: 200),
                    tokenFadeInCurve: Curves.linear,
                    tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      final double opacity = _activeTokenOpacity(tester);
      expect(opacity, greaterThan(0));
      expect(opacity, lessThan(1));
      return _captureRawRgba(tester, find.byKey(boundaryKey));
    }

    final Uint8List selectionDisabled =
        await capture(enableTextSelection: false);
    final Uint8List selectionEnabled = await capture(enableTextSelection: true);

    expect(selectionEnabled, orderedEquals(selectionDisabled));
  });

  testWidgets('custom token animation locks selection to source visual', (
    WidgetTester tester,
  ) async {
    const Color selectionColor = Color(0x6658A6FF);
    const String selectedBlock = 'Animated selection should stay anchored.';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[_renderNode(selectedBlock)],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.raw,
            tokenArrivalDelay: const Duration(milliseconds: 80),
            tokenFadeInDuration: const Duration(milliseconds: 600),
            tokenAnimationBuilder: (
              BuildContext context,
              StreamingMarkdownAnimatedToken token,
            ) {
              final double t = Curves.easeOutBack.transform(token.value);
              return Opacity(
                opacity: token.value,
                child: Transform.translate(
                  offset: Offset((1 - t) * -10, 0),
                  child: Transform.rotate(
                    angle: (1 - t) * -0.42,
                    alignment: Alignment.bottomLeft,
                    child: token.child,
                  ),
                ),
              );
            },
            markdownTheme: const StreamingMarkdownThemeData(
              selectionColor: selectionColor,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    const String selectedText = 'Animated';
    final Rect textRect = tester.getRect(find.text(selectedText));
    final Rect regionRect = tester.getRect(find.byType(SelectableRegion));
    final double startX =
        (textRect.left + 1).clamp(regionRect.left + 1, regionRect.right - 1);
    final Offset start = Offset(startX, textRect.top + 8);
    final Offset end = Offset(textRect.right + 4, textRect.top + 8);
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();

    expect(_highlightedTextForColor(tester, selectionColor), selectedText);
  });

  testWidgets('selection-enabled inline text keeps custom token animation idle',
      (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('one two three'),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            tokenArrivalDelay: const Duration(milliseconds: 100),
            tokenFadeInDuration: const Duration(milliseconds: 200),
            tokenAnimationBuilder: (
              BuildContext context,
              StreamingMarkdownAnimatedToken token,
            ) {
              return KeyedSubtree(
                key: const ValueKey<String>('selection-custom-token'),
                child: Opacity(opacity: token.value, child: token.child),
              );
            },
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const ValueKey<String>('selection-custom-token')),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('inline markdown images use image builder, not marker text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                'before ![small marker](https://example.com/marker.png) after.',
              ),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: Duration.zero,
            customImageBuilder: (
              BuildContext context,
              StreamingMarkdownImageBuildContext image,
            ) {
              return Text(
                '${image.state.name}:${image.inline}:${image.altText}',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('loading:true:small marker'), findsOneWidget);
    expect(find.textContaining('image: small marker'), findsNothing);
  });

  testWidgets('default inline markdown images gate surrounding content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                'before ![small marker](https://example.com/marker.png) after.',
              ),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    expect(find.textContaining('before'), findsNothing);
    expect(find.textContaining('after'), findsNothing);
    expect(find.textContaining('image: small marker'), findsNothing);
  });

  testWidgets('inline image alignment is exposed through render API', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                'before ![small marker](https://example.com/marker.png) after.',
              ),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: Duration.zero,
            inlineImageAlignment: PlaceholderAlignment.aboveBaseline,
            customImageBuilder: (
              BuildContext context,
              StreamingMarkdownImageBuildContext image,
            ) {
              return const SizedBox(width: 8, height: 8);
            },
          ),
        ),
      ),
    );

    final WidgetSpan imageSpan = _allWidgetSpans(tester).firstWhere(
        (WidgetSpan span) =>
            span.alignment == PlaceholderAlignment.aboveBaseline);
    expect(imageSpan.alignment, PlaceholderAlignment.aboveBaseline);
    expect(imageSpan.baseline, TextBaseline.alphabetic);
  });

  testWidgets('indented code block renders as a distinct code block', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                "    final value = 'Indented code block';",
                type: 'indented_code_block',
              ),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    expect(find.text('code'), findsAtLeastNWidgets(1));
    final String plainText = _richTextPlainTexts(tester).join('\n');
    expect(plainText, contains('final'));
    expect(plainText, contains('value'));
    expect(plainText, isNot(contains('    final')));
  });

  testWidgets('settled tokens compact to layout-stable token nodes', (
    WidgetTester tester,
  ) async {
    const String paragraph =
        'One two three four five six seven eight nine ten eleven twelve.';
    final GlobalKey rootKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: rootKey,
            width: 320,
            child: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[_renderNode(paragraph)],
              padding: EdgeInsets.zero,
              tokenArrivalDelay: const Duration(milliseconds: 20),
              tokenFadeInDuration: const Duration(milliseconds: 20),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(_totalWidgetSpanCount(tester), greaterThan(1));

    await tester.pump(const Duration(milliseconds: 260));
    final Size beforeCompaction = tester.getSize(find.byKey(rootKey));
    final int beforeCount = _totalWidgetSpanCount(tester);
    final int beforeHostCount = _fadeInTokenHostCount(tester);
    final Map<String, Rect> beforeRects = _rectsForTexts(
      tester,
      <String>['One', 'five', 'nine', 'twelve.'],
    );
    expect(beforeCount, greaterThan(1));
    expect(beforeHostCount, greaterThan(1));

    await tester.pump();
    final Size afterCompaction = tester.getSize(find.byKey(rootKey));
    final int afterCount = _totalWidgetSpanCount(tester);
    final int afterHostCount = _fadeInTokenHostCount(tester);
    final Map<String, Rect> afterRects = _rectsForTexts(
      tester,
      <String>['One', 'five', 'nine', 'twelve.'],
    );

    expect(afterCompaction, beforeCompaction);
    expect(afterCount, beforeCount);
    expect(afterHostCount, 0);
    _expectRectsClose(afterRects, beforeRects);
  });

  testWidgets('automatic token compaction strips custom animation hosts', (
    WidgetTester tester,
  ) async {
    const String paragraph = 'Custom animation compacts settled widgets.';
    final GlobalKey rootKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: rootKey,
            child: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[_renderNode(paragraph)],
              padding: EdgeInsets.zero,
              tokenArrivalDelay: const Duration(milliseconds: 20),
              tokenFadeInDuration: const Duration(milliseconds: 20),
              tokenAnimationBuilder: (
                BuildContext context,
                StreamingMarkdownAnimatedToken token,
              ) {
                return Opacity(opacity: token.value, child: token.child);
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(_totalWidgetSpanCount(tester), greaterThan(1));

    await tester.pump(const Duration(milliseconds: 260));
    final Size beforeCompaction = tester.getSize(find.byKey(rootKey));
    final int beforeHostCount = _fadeInTokenHostCount(tester);
    final Map<String, Rect> beforeRects = _rectsForTexts(
      tester,
      <String>['Custom', 'animation', 'settled', 'widgets.'],
    );
    expect(_totalWidgetSpanCount(tester), greaterThan(1));
    expect(beforeHostCount, greaterThan(1));

    await tester.pump();
    final Size afterCompaction = tester.getSize(find.byKey(rootKey));
    final int afterHostCount = _fadeInTokenHostCount(tester);
    final Map<String, Rect> afterRects = _rectsForTexts(
      tester,
      <String>['Custom', 'animation', 'settled', 'widgets.'],
    );

    expect(afterCompaction, beforeCompaction);
    expect(afterHostCount, 0);
    _expectRectsClose(afterRects, beforeRects);
  });

  testWidgets('selection container is absent when text selection is disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[_renderNode('Plain paragraph text')],
            padding: EdgeInsets.zero,
            enableTextSelection: false,
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('copy selection returns markdown source', (
    WidgetTester tester,
  ) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Inline [OpenAI](https://openai.com) link.'),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.raw,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    await _copySelection(tester);

    expect(clipboardText, 'Inline [OpenAI](https://openai.com) link.');
  });

  testWidgets('selection preserves received paragraph text during fade', (
    WidgetTester tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['text'] as String?;
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[_renderNode('Visible hidden future')],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.plain,
            tokenArrivalDelay: const Duration(seconds: 1),
            tokenFadeInDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    await tester.pump();

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    await _copySelection(tester);

    expect(clipboardText, 'Visible hidden future');
  });

  testWidgets('table selection excludes cells before their reveal begins', (
    WidgetTester tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['text'] as String?;
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

    const String table = '| Visible | Hidden |\n'
        '| --- | --- |\n'
        '| Future A | Future B |';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(table, type: 'pipe_table', endRow: 2),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.plain,
            tokenArrivalDelay: const Duration(seconds: 1),
            tokenFadeInDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    await tester.pump();

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    await _copySelection(tester);

    expect(clipboardText, 'Visible');
  });

  testWidgets('wrapped table selection paints using rendered token geometry', (
    WidgetTester tester,
  ) async {
    const Color selectionColor = Color(0x6658A6FF);
    await tester.binding.setSurfaceSize(const Size(340, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const String table = '| Task Goal | Recommended Model | Why? |\n'
        '| --- | --- | --- |\n'
        '| Story | Claude | Natural language |';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(table, type: 'pipe_table', endRow: 2),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.plain,
            tokenArrivalDelay: Duration.zero,
            tokenFadeInDuration: Duration.zero,
            tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
            markdownTheme: const StreamingMarkdownThemeData(
              selectionColor: selectionColor,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final Rect recommendedRect = tester.getRect(find.text('Recommended'));
    final Rect modelRect = tester.getRect(find.text('Model'));
    expect(modelRect.top, greaterThan(recommendedRect.top));

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final Iterable<Element> paintedBackdrops = find
        .byWidgetPredicate(
          (Widget widget) =>
              widget.runtimeType.toString() == '_InlineSourceSelectionBackdrop',
        )
        .evaluate()
        .where((Element element) {
      final dynamic widget = element.widget;
      return widget.selectionColor == selectionColor;
    });
    expect(paintedBackdrops, isEmpty);
    final String highlighted = _highlightedTextForColor(tester, selectionColor);
    expect(highlighted, contains('Recommended'));
    expect(highlighted, contains('Model'));
  });

  testWidgets('wrapped prose selection paints using rendered token geometry', (
    WidgetTester tester,
  ) async {
    const Color selectionColor = Color(0x6658A6FF);
    await tester.binding.setSurfaceSize(const Size(300, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const String paragraph =
        'Selected prose wraps onto following lines without drifting.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[_renderNode(paragraph)],
              padding: EdgeInsets.zero,
              enableTextSelection: true,
              selectionStrategy: SelectionStrategy.plain,
              tokenArrivalDelay: Duration.zero,
              tokenFadeInDuration: Duration.zero,
              tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
              markdownTheme: const StreamingMarkdownThemeData(
                selectionColor: selectionColor,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final Iterable<Element> paintedBackdrops = find
        .byWidgetPredicate(
          (Widget widget) =>
              widget.runtimeType.toString() == '_InlineSourceSelectionBackdrop',
        )
        .evaluate()
        .where((Element element) {
      final dynamic widget = element.widget;
      return widget.selectionColor == selectionColor;
    });
    expect(paintedBackdrops, isEmpty);
    final String highlighted = _highlightedTextForColor(
      tester,
      selectionColor,
    ).replaceAll(' ', '');
    expect(highlighted, contains('Selectedprosewraps'));
  });

  testWidgets('copy selection preserves block markdown delimiters', (
    WidgetTester tester,
  ) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '# Front matter',
                type: 'atx_heading',
                content: 'Front matter',
                startByte: 0,
              ),
              _renderNode(
                'Front matter is rendered as a metadata block when it appears '
                'at the top of the document.',
                startByte: 16,
              ),
              _renderNode(
                '---',
                type: 'thematic_break',
                content: '',
                startByte: 106,
              ),
              _renderNode(
                'Thematic breaks render as horizontal dividers.',
                startByte: 111,
              ),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.raw,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    await _copySelection(tester);

    expect(
      clipboardText,
      '# Front matter\n\n'
      'Front matter is rendered as a metadata block when it appears '
      'at the top of the document.\n\n'
      '---\n\n'
      'Thematic breaks render as horizontal dividers.',
    );
  });

  testWidgets(
      'locked markdown source selection survives transient shrink, append, and scroll',
      (WidgetTester tester) async {
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

    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode('Selected block one.', startByte: 0),
      _renderNode('Selected block two.', startByte: 21, startRow: 2),
    ];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: SizedBox(
                height: 120,
                child: ListView(
                  controller: scrollController,
                  children: <Widget>[
                    StreamingMarkdownRenderView(
                      nodes: nodes,
                      padding: EdgeInsets.zero,
                      enableTextSelection: true,
                      selectionStrategy: SelectionStrategy.raw,
                      tokenFadeInDuration: Duration.zero,
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    updateHost(() {
      nodes = <MarkdownRenderNode>[
        _renderNode('Selected block one.', startByte: 0),
      ];
    });
    await tester.pump();

    updateHost(() {
      nodes = <MarkdownRenderNode>[
        _renderNode('Selected block one.', startByte: 0),
        _renderNode('Selected block two.', startByte: 21, startRow: 2),
        _renderNode(
          'Appended while the user is scrolling.',
          startByte: 42,
          startRow: 4,
        ),
      ];
    });
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();

    await _copySelection(tester);

    expect(
      clipboardText,
      'Selected block one.\n\nSelected block two.',
    );
  });

  testWidgets('drag selection started while streaming remains source-stable',
      (WidgetTester tester) async {
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

    const String selectedBlock = 'Selected block one.';
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode(selectedBlock, startByte: 0),
      _renderNode(
        'Streaming block two is still fading in.',
        startByte: 21,
        startRow: 2,
      ),
    ];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: SizedBox(
                height: 120,
                child: ListView(
                  controller: scrollController,
                  children: <Widget>[
                    StreamingMarkdownRenderView(
                      nodes: nodes,
                      padding: EdgeInsets.zero,
                      enableTextSelection: true,
                      selectionStrategy: SelectionStrategy.raw,
                      tokenArrivalDelay: Duration.zero,
                      tokenFadeInDuration: Duration.zero,
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final RenderParagraph paragraph =
        _renderParagraphContaining(tester, selectedBlock);
    final TestGesture gesture = await tester.startGesture(
      _textOffsetToHitPosition(paragraph, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(
      _textOffsetToHitPosition(paragraph, selectedBlock.length, end: true),
    );
    await tester.pump();

    updateHost(() {
      nodes = <MarkdownRenderNode>[
        _renderNode(selectedBlock, startByte: 0),
        _renderNode(
          'Streaming block two is still fading in.',
          startByte: 21,
          startRow: 2,
        ),
        _renderNode(
          'A newly appended block lands while the mouse is still selecting.',
          startByte: 61,
          startRow: 4,
        ),
      ];
    });
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();

    final BuildContext context =
        tester.binding.focusManager.primaryFocus!.context!;
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, selectedBlock);
  });

  testWidgets('drag selection can span multiple markdown blocks',
      (WidgetTester tester) async {
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

    const String firstBlock = 'Alpha block begins.';
    const String secondBlock = 'Second block ends.';
    final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode(firstBlock, startByte: 0),
      _renderNode(
        secondBlock,
        startByte: firstBlock.length + 2,
        startRow: 2,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: nodes,
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.raw,
            tokenArrivalDelay: Duration.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph firstParagraph =
        _renderParagraphContaining(tester, firstBlock);
    final RenderParagraph secondParagraph =
        _renderParagraphContaining(tester, secondBlock);
    final TestGesture gesture = await tester.startGesture(
      _textOffsetToHitPosition(
        firstParagraph,
        firstBlock.indexOf('block'),
      ),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(
      _textOffsetToHitPosition(
        secondParagraph,
        secondBlock.indexOf('block') + 'block'.length,
        end: true,
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    final BuildContext context =
        tester.binding.focusManager.primaryFocus!.context!;
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, 'block begins.\n\nSecond block');
  });

  testWidgets('selection drag near viewport edge auto-scrolls ancestor',
      (WidgetTester tester) async {
    final ScrollController scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    const String firstBlock = 'Auto scroll selection anchor.';
    const String secondBlock = 'Auto scroll selection can continue below.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 120,
            child: ListView(
              controller: scrollController,
              children: <Widget>[
                StreamingMarkdownRenderView(
                  nodes: <MarkdownRenderNode>[
                    _renderNode(firstBlock, startByte: 0),
                    _renderNode(
                      secondBlock,
                      startByte: firstBlock.length + 2,
                      startRow: 2,
                    ),
                  ],
                  padding: EdgeInsets.zero,
                  enableTextSelection: true,
                  selectionStrategy: SelectionStrategy.raw,
                  tokenArrivalDelay: Duration.zero,
                  tokenFadeInDuration: Duration.zero,
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph paragraph =
        _renderParagraphContaining(tester, firstBlock);
    final Offset start = _textOffsetToHitPosition(paragraph, 0);
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(Offset(start.dx, 116));
    for (int i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final double bottomEdgeOffset = scrollController.offset;
    expect(bottomEdgeOffset, greaterThan(0));

    await gesture.moveTo(Offset(start.dx, 4));
    for (int i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollController.offset, lessThan(bottomEdgeOffset));

    await gesture.up();
    final double releasedOffset = scrollController.offset;
    await tester.pump(const Duration(milliseconds: 80));
    expect(scrollController.offset, releasedOffset);
  });

  testWidgets('auto-scroll selection keeps the upper anchor stable',
      (WidgetTester tester) async {
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

    const String firstBlock = 'Anchor starts here.';
    final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode(firstBlock, startByte: 0),
      for (int i = 0; i < 18; i += 1)
        _renderNode(
          'Auto-scroll block $i keeps extending the selected range.',
          startByte: firstBlock.length + 2 + i * 60,
          startRow: 2 + i * 2,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 120,
            child: ListView(
              controller: scrollController,
              children: <Widget>[
                StreamingMarkdownRenderView(
                  nodes: nodes,
                  padding: EdgeInsets.zero,
                  enableTextSelection: true,
                  selectionStrategy: SelectionStrategy.raw,
                  tokenArrivalDelay: Duration.zero,
                  tokenFadeInDuration: Duration.zero,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph paragraph =
        _renderParagraphContaining(tester, firstBlock);
    final TestGesture gesture = await tester.startGesture(
      _textOffsetToHitPosition(paragraph, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(const Offset(24, 116));
    for (int i = 0; i < 32; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollController.offset, greaterThan(0));
    await gesture.up();
    await tester.pump();

    final BuildContext context =
        tester.binding.focusManager.primaryFocus!.context!;
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, startsWith(firstBlock));
  });

  testWidgets('drag selection can continue below a markdown table',
      (WidgetTester tester) async {
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

    const String intro = 'Intro before table.';
    const String rawTable = '| Name | Status |\n'
        '| --- | --- |\n'
        '| Alpha | Ready |';
    const String after = 'After table target continues.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[
                _renderNode(intro, startByte: 0),
                _renderNode(
                  rawTable,
                  type: 'pipe_table',
                  startByte: intro.length + 2,
                  startRow: 2,
                  endRow: 4,
                ),
                _renderNode(
                  after,
                  startByte: intro.length + rawTable.length + 4,
                  startRow: 6,
                ),
              ],
              padding: EdgeInsets.zero,
              enableTextSelection: true,
              selectionStrategy: SelectionStrategy.raw,
              tokenArrivalDelay: Duration.zero,
              tokenFadeInDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph introParagraph =
        _renderParagraphContaining(tester, intro);
    final RenderParagraph tableParagraph =
        _renderParagraphContaining(tester, 'Ready');
    final RenderParagraph afterParagraph =
        _renderParagraphContaining(tester, after);
    final TestGesture gesture = await tester.startGesture(
      _textOffsetToHitPosition(introParagraph, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture
        .moveTo(_textOffsetToHitPosition(tableParagraph, 5, end: true));
    await tester.pump();
    await gesture.moveTo(
      _textOffsetToHitPosition(afterParagraph, after.length, end: true),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final BuildContext context =
        tester.binding.focusManager.primaryFocus!.context!;
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, contains(intro));
    expect(clipboardText, contains('| Name | Status |'));
    expect(clipboardText, contains(after));
  });

  testWidgets('table selection drag near horizontal edge auto-scrolls table',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(260, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const String rawTable = '| H0 | H1 | H2 | H3 | H4 | H5 | H6 |\n'
        '| --- | --- | --- | --- | --- | --- | --- |\n'
        '| A0 wide | A1 wide | A2 wide | A3 wide | A4 wide | A5 wide | A6 wide |';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                rawTable,
                type: 'pipe_table',
                startByte: 0,
                startRow: 0,
                endRow: 2,
              ),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.raw,
            tokenArrivalDelay: Duration.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump();

    final Rect tableFrame = tester
        .getRect(find.byKey(const ValueKey<String>('markdown_table_frame')));
    final RenderParagraph startParagraph =
        _renderParagraphContaining(tester, 'A0 wide');
    final TestGesture gesture = await tester.startGesture(
      _textOffsetToHitPosition(startParagraph, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(Offset(tableFrame.right - 2, tableFrame.center.dy));
    for (int i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final double rightEdgeOffset = _horizontalScrollPosition(tester).pixels;
    expect(rightEdgeOffset, greaterThan(0));

    await gesture.moveTo(Offset(tableFrame.left + 2, tableFrame.center.dy));
    for (int i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      _horizontalScrollPosition(tester).pixels,
      lessThan(rightEdgeOffset),
    );
    await gesture.up();
  });

  testWidgets('table corner drag advances horizontal and vertical axes',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(260, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ScrollController verticalController = ScrollController();
    addTearDown(verticalController.dispose);

    const String rawTable = '| H0 | H1 | H2 | H3 | H4 | H5 | H6 |\n'
        '| --- | --- | --- | --- | --- | --- | --- |\n'
        '| A0 wide | A1 wide | A2 wide | A3 wide | A4 wide | A5 wide | A6 wide |';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 160,
            child: ListView(
              controller: verticalController,
              children: <Widget>[
                const SizedBox(height: 72),
                StreamingMarkdownRenderView(
                  nodes: <MarkdownRenderNode>[
                    _renderNode(
                      rawTable,
                      type: 'pipe_table',
                      startByte: 0,
                      startRow: 0,
                      endRow: 2,
                    ),
                    for (int i = 0; i < 12; i += 1)
                      _renderNode(
                        'Following block $i keeps the vertical viewport moving.',
                        startByte: rawTable.length + 2 + i * 64,
                        startRow: 4 + i * 2,
                      ),
                  ],
                  padding: EdgeInsets.zero,
                  enableTextSelection: true,
                  selectionStrategy: SelectionStrategy.raw,
                  tokenArrivalDelay: Duration.zero,
                  tokenFadeInDuration: Duration.zero,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Rect tableFrame = tester
        .getRect(find.byKey(const ValueKey<String>('markdown_table_frame')));
    final double alignDelta = tableFrame.bottom - 158;
    if (alignDelta > 0) {
      verticalController.jumpTo(
        alignDelta.clamp(
          verticalController.position.minScrollExtent,
          verticalController.position.maxScrollExtent,
        ),
      );
      await tester.pump();
      tableFrame = tester
          .getRect(find.byKey(const ValueKey<String>('markdown_table_frame')));
    }

    final RenderParagraph startParagraph =
        _renderParagraphContaining(tester, 'A0 wide');
    final TestGesture gesture = await tester.startGesture(
      _textOffsetToHitPosition(startParagraph, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    final double initialVerticalOffset = verticalController.offset;
    await gesture.moveTo(
      Offset(
        tableFrame.right - 2,
        math.min(tableFrame.bottom - 2, 158),
      ),
    );
    for (int i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(_horizontalScrollPosition(tester).pixels, greaterThan(0));
    expect(verticalController.offset, greaterThan(initialVerticalOffset));
    await gesture.up();
  });

  testWidgets('RTL table edge drag follows reverse horizontal axis',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(260, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const String rawTable = '| H0 | H1 | H2 | H3 | H4 | H5 | H6 |\n'
        '| --- | --- | --- | --- | --- | --- | --- |\n'
        '| A0 wide | A1 wide | A2 wide | A3 wide | A4 wide | A5 wide | A6 wide |';
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[
                _renderNode(
                  rawTable,
                  type: 'pipe_table',
                  startByte: 0,
                  startRow: 0,
                  endRow: 2,
                ),
              ],
              padding: EdgeInsets.zero,
              enableTextSelection: true,
              selectionStrategy: SelectionStrategy.raw,
              tokenArrivalDelay: Duration.zero,
              tokenFadeInDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final ScrollPosition horizontalPosition = _horizontalScrollPosition(tester);
    expect(horizontalPosition.axisDirection, AxisDirection.left);

    final Rect tableFrame = tester
        .getRect(find.byKey(const ValueKey<String>('markdown_table_frame')));
    final RenderParagraph startParagraph = _visibleTableParagraph(
      tester,
      tableFrame,
      contains: 'wide',
    );
    final TestGesture gesture = await tester.startGesture(
      startParagraph.localToGlobal(startParagraph.size.center(Offset.zero)),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(Offset(tableFrame.left + 2, tableFrame.center.dy));
    for (int i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(horizontalPosition.pixels, greaterThan(0));
    await gesture.up();
  });

  testWidgets('stream append does not interrupt an active mouse selection drag',
      (WidgetTester tester) async {
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

    const String selectedBlock = 'Selected block one keeps extending.';
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode(selectedBlock, startByte: 0),
    ];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: nodes,
                padding: EdgeInsets.zero,
                enableTextSelection: true,
                selectionStrategy: SelectionStrategy.raw,
                tokenArrivalDelay: const Duration(milliseconds: 120),
                tokenFadeInDuration: const Duration(milliseconds: 900),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final TestGesture gesture = await tester.startGesture(
      _textWidgetHitPosition(tester, 'Selected'),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(_textWidgetHitPosition(tester, 'block', end: true));
    await tester.pump();

    updateHost(() {
      nodes = <MarkdownRenderNode>[
        _renderNode(selectedBlock, startByte: 0),
        _renderNode(
          'A streamed block arrives before the drag is released.',
          startByte: selectedBlock.length + 2,
          startRow: 2,
        ),
      ];
    });
    await tester.pump(const Duration(milliseconds: 600));
    await gesture
        .moveTo(_textWidgetHitPosition(tester, 'extending.', end: true));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    final BuildContext context =
        tester.binding.focusManager.primaryFocus!.context!;
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, selectedBlock);
  });

  testWidgets('stream append after selection locks source visual',
      (WidgetTester tester) async {
    const Color selectionColor = Color(0x6658A6FF);
    const String selectedBlock = 'Selected block one stays anchored.';
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode(selectedBlock, startByte: 0),
    ];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: nodes,
                padding: EdgeInsets.zero,
                enableTextSelection: true,
                selectionStrategy: SelectionStrategy.raw,
                tokenArrivalDelay: const Duration(milliseconds: 120),
                tokenFadeInDuration: const Duration(milliseconds: 900),
                markdownTheme: const StreamingMarkdownThemeData(
                  selectionColor: selectionColor,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    const String selectedText = 'Selected';
    final TestGesture gesture = await tester.startGesture(
      _textWidgetHitPosition(tester, selectedText),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture
        .moveTo(_textWidgetHitPosition(tester, selectedText, end: true));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    expect(_highlightedTextForColor(tester, selectionColor), selectedText);

    updateHost(() {
      nodes = <MarkdownRenderNode>[
        _renderNode(selectedBlock, startByte: 0),
        _renderNode(
          'A streamed block arrives after selection has finalized.',
          startByte: selectedBlock.length + 2,
          startRow: 2,
        ),
      ];
    });
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(_highlightedTextForColor(tester, selectionColor), selectedText);
  });

  testWidgets('finalized animated selection remains natively draggable',
      (WidgetTester tester) async {
    const String selectedText = 'Stable';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                  '$selectedText selection remains draggable after release.'),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.plain,
            tokenArrivalDelay: const Duration(milliseconds: 80),
            tokenFadeInDuration: const Duration(milliseconds: 150),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final TestGesture gesture = await tester.startGesture(
      _textWidgetHitPosition(tester, selectedText),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(
      _textWidgetHitPosition(tester, selectedText, end: true),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(_proxySelectedText(tester), contains(selectedText));
  });

  testWidgets('replacement drag moves the flat selection before release',
      (WidgetTester tester) async {
    const Color selectionColor = Color(0x6658A6FF);
    const String firstText = 'Stable';
    const String replacementText = 'replacement';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '$firstText $replacementText remains easy to select.',
              ),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.plain,
            tokenArrivalDelay: const Duration(milliseconds: 40),
            tokenFadeInDuration: const Duration(milliseconds: 160),
            tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
            markdownTheme: const StreamingMarkdownThemeData(
              selectionColor: selectionColor,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    TestGesture gesture = await tester.startGesture(
      _textWidgetHitPosition(tester, firstText),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(
      _textWidgetHitPosition(tester, firstText, end: true),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(_highlightedTextForColor(tester, selectionColor), firstText);

    gesture = await tester.startGesture(
      _textWidgetHitPosition(tester, replacementText),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(
      _textWidgetHitPosition(tester, replacementText, end: true),
    );
    await tester.pump();

    expect(
      _highlightedTextForColor(tester, selectionColor),
      replacementText,
    );

    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(_proxySelectedText(tester), contains(replacementText));
    expect(_highlightedTextForColor(tester, selectionColor), replacementText);
  });

  testWidgets('locked scroll selection can be replaced by a new drag selection',
      (WidgetTester tester) async {
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

    const String firstBlock = 'First block becomes locked.';
    const String secondBlock = 'Second block must be selectable after lock.';
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode(firstBlock, startByte: 0),
      _renderNode(
        secondBlock,
        startByte: firstBlock.length + 2,
        startRow: 2,
      ),
    ];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: SizedBox(
                height: 110,
                child: ListView(
                  controller: scrollController,
                  children: <Widget>[
                    StreamingMarkdownRenderView(
                      nodes: nodes,
                      padding: EdgeInsets.zero,
                      enableTextSelection: true,
                      selectionStrategy: SelectionStrategy.raw,
                      tokenArrivalDelay: Duration.zero,
                      tokenFadeInDuration: Duration.zero,
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    RenderParagraph paragraph = _renderParagraphContaining(tester, firstBlock);
    TestGesture gesture = await tester.startGesture(
      _textOffsetToHitPosition(paragraph, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(
      _textOffsetToHitPosition(paragraph, firstBlock.length, end: true),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    scrollController.jumpTo(10);
    updateHost(() {
      nodes = <MarkdownRenderNode>[
        _renderNode(firstBlock, startByte: 0),
        _renderNode(
          secondBlock,
          startByte: firstBlock.length + 2,
          startRow: 2,
        ),
        _renderNode(
          'Append while the previous selection is locked.',
          startByte: firstBlock.length + secondBlock.length + 4,
          startRow: 4,
        ),
      ];
    });
    await tester.pump(const Duration(seconds: 2));

    paragraph = _renderParagraphContaining(tester, secondBlock);
    gesture = await tester.startGesture(
      _textOffsetToHitPosition(paragraph, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(
      _textOffsetToHitPosition(paragraph, secondBlock.length, end: true),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    final BuildContext context =
        tester.binding.focusManager.primaryFocus!.context!;
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, secondBlock);
  });

  testWidgets('scroll during active streaming selection freezes source range',
      (WidgetTester tester) async {
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

    const String selectedBlock = 'Selected block one.';
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _renderNode(selectedBlock, startByte: 0),
      _renderNode(
        'Streaming block two is visible while selection starts.',
        startByte: 21,
        startRow: 2,
      ),
    ];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: SizedBox(
                height: 120,
                child: ListView(
                  controller: scrollController,
                  children: <Widget>[
                    StreamingMarkdownRenderView(
                      nodes: nodes,
                      padding: EdgeInsets.zero,
                      enableTextSelection: true,
                      selectionStrategy: SelectionStrategy.raw,
                      tokenArrivalDelay: const Duration(milliseconds: 120),
                      tokenFadeInDuration: const Duration(milliseconds: 900),
                    ),
                    const SizedBox(height: 500),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final TestGesture gesture = await tester.startGesture(
      _textWidgetHitPosition(tester, 'Selected'),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(_textWidgetHitPosition(tester, 'one.', end: true));
    await tester.pump();

    unawaited(
      scrollController.animateTo(
        80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.linear,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    updateHost(() {
      nodes = <MarkdownRenderNode>[
        _renderNode(selectedBlock, startByte: 0),
        _renderNode(
          'Streaming block two is visible while selection starts.',
          startByte: 21,
          startRow: 2,
        ),
        _renderNode(
          'Append lands while the existing selection is being scrolled.',
          startByte: 73,
          startRow: 4,
        ),
      ];
    });
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();

    final BuildContext context =
        tester.binding.focusManager.primaryFocus!.context!;
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, selectedBlock);
  });

  testWidgets('copy select-all preserves markdown for complex blocks', (
    WidgetTester tester,
  ) async {
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

    const String code = r'''```dart
class Greeter {
  const Greeter(this.name);

  final String name;

  String call() => 'Hello, $name';
}
```''';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '# Copy Audit',
                type: 'atx_heading',
                content: 'Copy Audit',
                startByte: 0,
                startRow: 0,
              ),
              _renderNode('Paragraph **bold**.', startByte: 20, startRow: 2),
              _renderNode(
                '- one\n- two',
                type: 'list',
                startByte: 42,
                startRow: 4,
                endRow: 5,
              ),
              _renderNode(
                '> quoted line\n> second line',
                type: 'block_quote',
                startByte: 55,
                startRow: 7,
                endRow: 8,
              ),
              _renderNode(
                code,
                type: 'fenced_code_block',
                startByte: 85,
                startRow: 10,
                endRow: 13,
              ),
              _renderNode(
                '| Name | Status |',
                type: 'pipe_table_header',
                startByte: 125,
                startRow: 15,
              ),
              _renderNode(
                '| --- | --- |',
                type: 'pipe_table_delimiter_row',
                startByte: 143,
                startRow: 16,
              ),
              _renderNode(
                '| Alpha | **Ready** |',
                type: 'pipe_table_row',
                startByte: 157,
                startRow: 17,
              ),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.raw,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    await _copySelection(tester);

    expect(
      clipboardText,
      '# Copy Audit\n\n'
      'Paragraph **bold**.\n\n'
      '- one\n'
      '- two\n\n'
      '> quoted line\n'
      '> second line\n\n'
      '$code\n\n'
      '| Name | Status |\n'
      '| --- | --- |\n'
      '| Alpha | **Ready** |',
    );
  });

  testWidgets('copy select-all includes blocks after footnotes', (
    WidgetTester tester,
  ) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '# Footnotes',
                type: 'atx_heading',
                content: 'Footnotes',
                startByte: 0,
                startRow: 0,
              ),
              _renderNode(
                'Streaming render can show footnote references inline.[^parser]',
                startByte: 13,
                startRow: 2,
              ),
              _renderNode(
                'Multiple references can point at separate definitions.[^renderer]',
                startByte: 76,
                startRow: 4,
              ),
              _renderNode(
                '[^parser]: The parser emits footnote definition nodes.\n'
                '[^renderer]: The renderer displays definitions as compact rows.',
                type: 'footnote_definition',
                startByte: 141,
                startRow: 6,
                endRow: 7,
              ),
              _renderNode(
                '# HTML blocks',
                type: 'atx_heading',
                content: 'HTML blocks',
                startByte: 256,
                startRow: 9,
              ),
              _renderNode(
                '<section>\n  <h2>HTML block</h2>\n</section>',
                type: 'html_block',
                startByte: 271,
                startRow: 11,
                endRow: 13,
              ),
            ],
            padding: EdgeInsets.zero,
            enableTextSelection: true,
            selectionStrategy: SelectionStrategy.raw,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    await _copySelection(tester);

    expect(
      clipboardText,
      '# Footnotes\n\n'
      'Streaming render can show footnote references inline.[^parser]\n\n'
      'Multiple references can point at separate definitions.[^renderer]\n\n'
      '[^parser]: The parser emits footnote definition nodes.\n'
      '[^renderer]: The renderer displays definitions as compact rows.\n\n'
      '# HTML blocks\n\n'
      '<section>\n  <h2>HTML block</h2>\n</section>',
    );
  });

  testWidgets(
    'resize and selection toggle do not restart fade (sliver=false)',
    (WidgetTester tester) async {
      bool selectionEnabled = false;
      Size viewportSize = const Size(1200, 800);
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return MediaQuery(
                data: MediaQueryData(size: viewportSize),
                child: Scaffold(
                  body: StreamingMarkdownRenderView(
                    nodes: <MarkdownRenderNode>[
                      _renderNode('Token fade should continue'),
                    ],
                    padding: EdgeInsets.zero,
                    enableTextSelection: selectionEnabled,
                    tokenFadeInDuration: const Duration(seconds: 2),
                    tokenFadeInCurve: Curves.linear,
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));
      final double beforeResize = _activeTokenOpacity(tester);

      updateHost(() {
        viewportSize = const Size(920, 800);
      });
      await tester.pump();
      final double afterResize = _activeTokenOpacity(tester);

      updateHost(() {
        selectionEnabled = true;
      });
      await tester.pump();
      final double afterSelectionToggle = _activeTokenOpacity(tester);

      if (beforeResize == 0) {
        expect(afterResize, 0);
        expect(afterSelectionToggle, greaterThanOrEqualTo(0));
      } else {
        expect(afterResize, greaterThan(beforeResize - 0.2));
        expect(afterSelectionToggle, greaterThanOrEqualTo(0));
      }
    },
  );

  testWidgets('app lifecycle changes do not restart a revealed token', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Lifecycle token remains generated'),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: const Duration(seconds: 2),
            tokenFadeInCurve: Curves.linear,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 700));
    final double beforePause = _activeTokenOpacity(tester);
    expect(beforePause, greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final double afterResume = _activeTokenOpacity(tester);

    expect(afterResume, greaterThanOrEqualTo(beforePause - 0.2));
  });

  testWidgets('reordered block layout keeps existing token animation state', (
    WidgetTester tester,
  ) async {
    final MarkdownRenderNode existing = _renderNode(
      'Existingstableword should continue fading',
      startByte: 40,
    );
    final MarkdownRenderNode inserted = _renderNode(
      'Inserted block',
      startByte: 0,
    );
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[existing];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: nodes,
                padding: EdgeInsets.zero,
                tokenFadeInDuration: const Duration(seconds: 2),
                tokenFadeInCurve: Curves.linear,
                tokenAnimationBuilder:
                    (BuildContext context, AnimatedMarkdownToken token) {
                  final Widget child = token.child;
                  final Key? key = child is Text
                      ? ValueKey<String>('token_${child.data}')
                      : null;
                  return Opacity(
                    key: key,
                    opacity: token.value,
                    child: child,
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 700));
    final double beforeInsert = _opacityByKey(
      tester,
      const ValueKey<String>('token_Existingstableword'),
    );
    expect(beforeInsert, greaterThan(0));

    updateHost(() {
      nodes = <MarkdownRenderNode>[inserted, existing];
    });
    await tester.pump();
    final double afterInsert = _opacityByKey(
      tester,
      const ValueKey<String>('token_Existingstableword'),
    );

    expect(afterInsert, greaterThan(beforeInsert - 0.2));
  });

  testWidgets('reordered sliver layout keeps existing token animation state', (
    WidgetTester tester,
  ) async {
    final MarkdownRenderNode existing = _renderNode(
      'Sliverstableword should continue fading',
      startByte: 40,
    );
    final MarkdownRenderNode inserted = _renderNode(
      'Inserted sliver block',
      startByte: 0,
    );
    List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[existing];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  StreamingMarkdownRenderView(
                    nodes: nodes,
                    sliver: true,
                    padding: EdgeInsets.zero,
                    tokenFadeInDuration: const Duration(seconds: 2),
                    tokenFadeInCurve: Curves.linear,
                    tokenAnimationBuilder:
                        (BuildContext context, AnimatedMarkdownToken token) {
                      final Widget child = token.child;
                      final Key? key = child is Text
                          ? ValueKey<String>('token_${child.data}')
                          : null;
                      return Opacity(
                        key: key,
                        opacity: token.value,
                        child: child,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 700));
    final double beforeInsert = _opacityByKey(
      tester,
      const ValueKey<String>('token_Sliverstableword'),
    );
    expect(beforeInsert, greaterThan(0));

    updateHost(() {
      nodes = <MarkdownRenderNode>[inserted, existing];
    });
    await tester.pump();
    final double afterInsert = _opacityByKey(
      tester,
      const ValueKey<String>('token_Sliverstableword'),
    );

    expect(afterInsert, greaterThan(beforeInsert - 0.2));
  });

  testWidgets('resize does not restart fade (sliver=true)', (
    WidgetTester tester,
  ) async {
    Size viewportSize = const Size(1200, 800);
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            updateHost = setState;
            return MediaQuery(
              data: MediaQueryData(size: viewportSize),
              child: Scaffold(
                body: AnimatedStreamingMarkdownSelectionArea(
                  child: CustomScrollView(
                    slivers: <Widget>[
                      StreamingMarkdownRenderView(
                        nodes: <MarkdownRenderNode>[
                          _renderNode('Token fade should continue'),
                        ],
                        sliver: true,
                        padding: EdgeInsets.zero,
                        enableTextSelection: true,
                        tokenFadeInDuration: const Duration(seconds: 2),
                        tokenFadeInCurve: Curves.linear,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 700));
    final double beforeResize = _activeTokenOpacity(tester);

    updateHost(() {
      viewportSize = const Size(920, 800);
    });
    await tester.pump();
    final double afterResize = _activeTokenOpacity(tester);

    expect(afterResize, greaterThan(beforeResize - 0.2));
  });

  testWidgets('html tables use intrinsic columns', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('''
<table>
  <tr><th>Column</th><th>Value</th></tr>
  <tr><td>HTML table</td><td>Rendered</td></tr>
</table>
''', type: 'html_block'),
            ],
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    final Table table = tester.widget<Table>(find.byType(Table));

    expect(table.defaultColumnWidth, isA<IntrinsicColumnWidth>());
    expect(find.text('HTML table'), findsOneWidget);
    expect(find.text('Rendered'), findsOneWidget);
  });

  testWidgets('html inline links are tappable', (WidgetTester tester) async {
    String? tappedUrl;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '<p>Visit <a href="https://dart.dev">Dart</a>.</p>',
                type: 'html_block',
              ),
            ],
            padding: EdgeInsets.zero,
            onLinkTap: (String url) {
              tappedUrl = url;
            },
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.text('Dart')));

    expect(tappedUrl, 'https://dart.dev');
  });

  testWidgets('inline and display LaTeX render through KaTeX math widgets',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown:
                r'Inline $x^2 + y^2 = z^2$ works.' '\n\n' r'$$\frac{a}{b}$$',
            tokenAnimationDuration: Duration.zero,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'$x^2 + y^2 = z^2$'), findsNothing);
  });

  testWidgets('stretched LaTeX keeps finite layout and baseline geometry',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown: r'''
Before $\left(\frac{\sqrt{x^2 + 1}}{\sum_{i=1}^{n} i}\right)$ after.

$$\sqrt{\frac{a+b}{c+d}} + \left[\sum_{k=0}^{m} k^2\right]$$
''',
            tokenAnimationDuration: Duration.zero,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.byType(SelectableText), findsNothing);
    for (int index = 0; index < 2; index++) {
      final Size size = tester.getSize(find.byType(Math).at(index));
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(size, isNot(Size.zero));
    }
  });

  testWidgets('footnotes render as numbered references and definitions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Has a note[^alpha].', startByte: 0),
              _renderNode(
                '[^alpha]: Definition body',
                type: 'footnote_definition',
                startByte: 20,
              ),
            ],
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(_footnoteLabel('alpha'), findsOneWidget);
    expect(find.text('[alpha]'), findsNothing);
  });

  testWidgets('combined footnote definitions render on separate rows', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '[^parser]: Parser definition\n'
                '[^renderer]: Renderer definition',
                type: 'footnote_definition',
              ),
            ],
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    final Finder parserLine = _footnoteLabel('parser');
    final Finder rendererLine = _footnoteLabel('renderer');

    expect(parserLine, findsOneWidget);
    expect(rendererLine, findsOneWidget);

    final Rect parserRect = tester.getRect(parserLine);
    final Rect rendererRect = tester.getRect(rendererLine);

    expect(rendererRect.top, greaterThan(parserRect.bottom));
  });

  testWidgets('wrapped footnote definitions do not share a visual line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[
                _renderNode(
                  '[^parser]: The parser emits footnote definition nodes.\n'
                  '[^renderer]: The renderer displays definitions as compact rows.',
                  type: 'footnote_definition',
                ),
              ],
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );

    final Finder parserLine = _footnoteLabel('parser');
    final Finder rendererLine = _footnoteLabel('renderer');

    expect(parserLine, findsOneWidget);
    expect(rendererLine, findsOneWidget);

    final Rect parserLabel = tester.getRect(parserLine);
    final Rect rendererLabel = tester.getRect(rendererLine);

    expect(rendererLabel.top, greaterThan(parserLabel.bottom));
  });

  testWidgets('link reference typed footnotes render on separate rows', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '[^parser]: The parser emits footnote definition nodes.\n'
                '[^renderer]: The renderer displays definitions as compact rows.',
                type: 'link_reference_definition',
              ),
            ],
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    final Finder parserLine = _footnoteLabel('parser');
    final Finder rendererLine = _footnoteLabel('renderer');

    expect(parserLine, findsOneWidget);
    expect(rendererLine, findsOneWidget);
    expect(
      tester.getRect(rendererLine).top,
      greaterThan(tester.getRect(parserLine).bottom),
    );
  });

  testWidgets('separate link reference footnote nodes render on separate rows',
      (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '[^parser]: The parser emits footnote definition nodes.',
                type: 'link_reference_definition',
                startByte: 0,
                startRow: 0,
                endRow: 0,
              ),
              _renderNode(
                '[^renderer]: The renderer displays definitions as compact rows.',
                type: 'link_reference_definition',
                startByte: 56,
                startRow: 1,
                endRow: 1,
              ),
            ],
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    final Finder parserLine = _footnoteLabel('parser');
    final Finder rendererLine = _footnoteLabel('renderer');

    expect(parserLine, findsOneWidget);
    expect(rendererLine, findsOneWidget);
    expect(
      tester.getRect(rendererLine).top,
      greaterThan(tester.getRect(parserLine).bottom),
    );
  });

  testWidgets('paragraph typed footnote definitions render on separate rows', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '[^parser]: The parser emits footnote definition nodes.\n'
                '[^renderer]: The renderer displays definitions as compact rows.',
                type: 'paragraph',
              ),
            ],
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    final Finder parserLine = _footnoteLabel('parser');
    final Finder rendererLine = _footnoteLabel('renderer');

    expect(parserLine, findsOneWidget);
    expect(rendererLine, findsOneWidget);
    expect(
      tester.getRect(rendererLine).top,
      greaterThan(tester.getRect(parserLine).bottom),
    );
  });

  testWidgets('underscore delimiters do not add underline decoration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('_italic_'),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    final Text text = tester.widget<Text>(find.text('italic'));
    expect(text.style?.fontStyle, FontStyle.italic);
    expect(text.style?.decoration, isNot(TextDecoration.underline));
  });

  testWidgets('setext headings hide delimiter lines from content and raw', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                'Setext heading level 1\n======================',
                type: 'setext_heading',
                content: 'Setext heading level 1\n======================',
                endRow: 1,
              ),
              _renderNode(
                'Setext heading level 2\n----------------------',
                type: 'setext_heading',
                content: '',
                startByte: 45,
                startRow: 3,
                endRow: 4,
              ),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    final String renderedText = _richTextPlainTexts(tester).join('\n');
    expect(renderedText, contains('Setext'));
    expect(renderedText, contains('heading'));
    expect(renderedText, contains('level'));
    expect(renderedText, contains('1'));
    expect(renderedText, contains('2'));
    expect(renderedText, isNot(contains('=')));
    expect(renderedText, isNot(contains('---')));
  });

  testWidgets('intraword underscores render literally', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Open pub_dev package'),
            ],
            padding: EdgeInsets.zero,
            allowUnclosedInlineDelimiters: true,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    final String renderedText = _richTextPlainTexts(tester).join('\n');
    expect(renderedText, contains('pub_dev'));
  });

  testWidgets('underscore thematic breaks render as dividers only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('Before'),
              _renderNode('___', type: 'thematic_break', content: ''),
              _renderNode('After', startByte: 10),
            ],
            padding: EdgeInsets.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    expect(find.byType(Divider), findsOneWidget);
    expect(_richTextPlainTexts(tester).join('\n'), isNot(contains('___')));
  });

  testWidgets('unrevealed list items do not occupy layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('- first\n- second', type: 'list'),
            ],
            padding: EdgeInsets.zero,
            tokenArrivalDelay: const Duration(milliseconds: 500),
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('second table does not render before first table tokens complete',
      (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '| A | B |\n| --- | --- |\n| C | D |',
                type: 'pipe_table',
                startByte: 0,
                startRow: 0,
                endRow: 2,
              ),
              _renderNode(
                '| E | F |\n| --- | --- |\n| G | H |',
                type: 'pipe_table',
                startByte: 34,
                startRow: 4,
                endRow: 6,
              ),
            ],
            padding: EdgeInsets.zero,
            tokenArrivalDelay: const Duration(milliseconds: 100),
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('E'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('markdown tables keep pipes inside inline code cells', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '| Case | Markdown | Rendered behavior |',
                type: 'pipe_table_header',
                startByte: 0,
                startRow: 0,
              ),
              _renderNode(
                '| :--- | :------: | ---------------: |',
                type: 'pipe_table_delimiter_row',
                startByte: 39,
                startRow: 1,
              ),
              _renderNode(
                '| Inline code | `a | b` | Keeps pipe inside code |',
                type: 'pipe_table_row',
                startByte: 78,
                startRow: 2,
              ),
              _renderNode(
                r'| Escaped pipe | `a \| b` | Keeps escaped separator |',
                type: 'pipe_table_row',
                startByte: 131,
                startRow: 3,
              ),
              _renderNode(
                '| Link | [docs](https://docs.flutter.dev) | '
                'Tappable cell content |',
                type: 'pipe_table_row',
                startByte: 187,
                startRow: 4,
              ),
            ],
            padding: EdgeInsets.zero,
            tokenArrivalDelay: Duration.zero,
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('markdown_table_frame')),
      findsOneWidget,
    );
    for (int row = 0; row < 4; row++) {
      expect(
        find.byKey(ValueKey<String>('markdown_table_row_$row')),
        findsOneWidget,
      );
    }

    final List<String> plainTexts = _richTextPlainTexts(tester);
    expect(
        plainTexts,
        containsAll(<String>[
          'Case',
          'Markdown',
          'Rendered behavior',
          'Inline code',
          'Keeps pipe inside code',
          'Escaped pipe',
          'Keeps escaped separator',
          'docs',
          'Tappable cell content',
        ]));
    expect(plainTexts.where((String text) => text == 'a | b'), hasLength(2));
  });

  testWidgets('markdown tables render LaTeX cells with formula pipes', (
    WidgetTester tester,
  ) async {
    const String markdown = r'''
| Công thức | Laplace | Ghi chú |
| --- | --- | --- |
| Định nghĩa | $\mathcal{L}\{f(t)\}=\int_0^\infty e^{-st}f(t)\,dt \left|_{0}^{\infty}$ | inline |
| Đạo hàm | $$\mathcal{L}\{f'(t)\}=sF(s)-f(0)$$ | display |
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown: markdown,
            tokenAnimationDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('markdown_table_frame')),
      findsOneWidget,
    );
    for (int row = 0; row < 3; row++) {
      expect(
        find.byKey(ValueKey<String>('markdown_table_row_$row')),
        findsOneWidget,
      );
    }
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining(r'\left|'), findsNothing);
  });

  testWidgets('streamed response keeps LaTeX table stable while appending', (
    WidgetTester tester,
  ) async {
    const String markdown = r'''
Các công thức Laplace:

| Tên | Công thức |
| --- | --- |
| Định nghĩa | $\mathcal{L}\{f(t)\}=\int_0^\infty e^{-st}f(t)\,dt \left|_{0}^{\infty}$ |
| Đạo hàm | $\mathcal{L}\{f(t)\}=F(s)$ |
''';
    final ValueNotifier<List<MarkdownBlock>> blocks =
        ValueNotifier<List<MarkdownBlock>>(const <MarkdownBlock>[]);

    addTearDown(() {
      blocks.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<MarkdownBlock>>(
            valueListenable: blocks,
            builder: (BuildContext context, List<MarkdownBlock> value, _) {
              return AnimatedStreamingMarkdown(
                blocks: value,
                tokenStaggerDelay: const Duration(milliseconds: 20),
                tokenAnimationDuration: const Duration(milliseconds: 20),
                allowIncompleteInlineSyntax: true,
              );
            },
          ),
        ),
      ),
    );

    final StringBuffer streamed = StringBuffer();
    for (final String chunk in _chunkString(markdown, 18)) {
      streamed.write(chunk);
      final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
        streamed.toString(),
      );
      blocks.value = result.blocks;
      await tester.pump(const Duration(milliseconds: 24));
    }
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(_richTextPlainTexts(tester).join('\n'), contains('Laplace'));
    expect(
      find.byKey(const ValueKey<String>('markdown_table_frame')),
      findsOneWidget,
    );
    for (int row = 0; row < 3; row++) {
      expect(
        find.byKey(ValueKey<String>('markdown_table_row_$row')),
        findsOneWidget,
      );
    }
    expect(find.byType(Math), findsWidgets);
  });

  testWidgets('table layout stays stable while cell tokens reveal', (
    WidgetTester tester,
  ) async {
    const String markdown = '''
| Name | Notes |
| --- | --- |
| Laplace | This row contains a much longer explanation that would normally stretch while tokens appear. |
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown: markdown,
            tokenStaggerDelay: const Duration(milliseconds: 60),
            tokenAnimationDuration: const Duration(milliseconds: 120),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byKey(const ValueKey<String>('markdown_table_frame')),
        findsOneWidget);
    final Size initialSize = tester.getSize(
      find.byKey(const ValueKey<String>('markdown_table_frame')),
    );

    await tester.pump(const Duration(milliseconds: 240));
    final Size midSize = tester.getSize(
      find.byKey(const ValueKey<String>('markdown_table_frame')),
    );

    await tester.pumpAndSettle();
    final Size finalSize = tester.getSize(
      find.byKey(const ValueKey<String>('markdown_table_frame')),
    );

    expect(midSize, finalSize);
    expect(initialSize.height, lessThan(finalSize.height));
  });

  testWidgets('markdown tables reveal body rows progressively', (
    WidgetTester tester,
  ) async {
    const String markdown = '''
| Name | Notes |
| --- | --- |
| Laplace | First visible row |
| Fourier | Second row should wait |
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedStreamingMarkdown.fromMarkdown(
            markdown: markdown,
            tokenStaggerDelay: const Duration(milliseconds: 90),
            tokenAnimationDuration: const Duration(milliseconds: 60),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Laplace'), findsNothing);
    expect(find.text('Fourier'), findsNothing);

    await tester.pump(const Duration(milliseconds: 260));
    expect(find.text('Laplace'), findsOneWidget);
    expect(find.text('Fourier'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Fourier'), findsOneWidget);
  });

  testWidgets('table delimiter rows do not render as text or add token wait', (
    WidgetTester tester,
  ) async {
    int waits = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('| --- | --- |', type: 'pipe_table_delimiter_row'),
            ],
            padding: EdgeInsets.zero,
            tokenArrivalDelay: const Duration(milliseconds: 100),
            onTokenArrivalWait: () {
              waits += 1;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('---'), findsNothing);
    expect(waits, 1);
  });

  testWidgets('empty table delimiter cells do not render table chrome', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('| --- | --- |', type: 'pipe_table'),
            ],
            padding: EdgeInsets.zero,
            tokenArrivalDelay: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );

    expect(find.textContaining('---'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('markdown_table_frame')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('markdown_table_frame')))
          .height,
      0,
    );
  });

  testWidgets('footnote definition body uses token fade animation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '[^parser]: The parser emits footnote definition nodes.',
                type: 'paragraph',
              ),
            ],
            padding: EdgeInsets.zero,
            tokenArrivalDelay: const Duration(milliseconds: 80),
            tokenFadeInDuration: const Duration(seconds: 2),
            tokenFadeInCurve: Curves.linear,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(_footnoteLabel('parser'), findsOneWidget);
    expect(find.text('The'), findsOneWidget);
    expect(_activeTokenOpacity(tester), greaterThan(0));
    expect(_activeTokenOpacity(tester), lessThan(1));
  });

  testWidgets('task list checkbox aligns with item text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode('- [ ] Open task', type: 'list'),
            ],
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );

    final Offset checkboxCenter = tester.getCenter(
      find.byIcon(Icons.check_box_outline_blank),
    );
    final Offset textCenter = tester.getCenter(find.text('Open'));

    // Flutter 3.10 and current stable use slightly different Material icon and
    // text metrics. Four logical pixels keeps the visual centers on the same
    // line while avoiding an engine-version-specific assertion.
    expect((checkboxCenter.dy - textCenter.dy).abs(), lessThanOrEqualTo(4));
  });
}

Set<String> _collectTypes(MarkdownSyntaxNode node) {
  final Set<String> out = <String>{node.type};
  for (final MarkdownSyntaxNode child in node.children) {
    out.addAll(_collectTypes(child));
  }
  return out;
}

List<String> _richTextPlainTexts(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((RichText widget) => widget.text.toPlainText())
      .toList(growable: false);
}

Iterable<String> _chunkString(String value, int chunkLength) sync* {
  var index = 0;
  while (index < value.length) {
    final int end = (index + chunkLength).clamp(0, value.length);
    yield value.substring(index, end);
    index = end;
  }
}

MarkdownRenderNode _renderNode(
  String raw, {
  String type = 'paragraph',
  String? content,
  int startByte = 0,
  int startRow = 0,
  int? endRow,
}) {
  return MarkdownRenderNode(
    type: type,
    depth: 0,
    startByte: startByte,
    endByte: startByte + raw.length,
    startRow: startRow,
    endRow: endRow ?? startRow,
    raw: raw,
    content: content ?? raw,
  );
}

double _activeTokenOpacity(WidgetTester tester) {
  final List<double> activeOpacities = tester
      .widgetList<Opacity>(find.byType(Opacity))
      .map((Opacity widget) => widget.opacity)
      .where((double value) => value > 0 && value < 1)
      .toList(growable: false);
  if (activeOpacities.isNotEmpty) {
    return activeOpacities.first;
  }

  final List<double> activeFadeTransitions = tester
      .widgetList<FadeTransition>(find.byType(FadeTransition))
      .map((FadeTransition widget) => widget.opacity.value)
      .where((double value) => value > 0 && value < 1)
      .toList(growable: false);
  if (activeFadeTransitions.isNotEmpty) {
    return activeFadeTransitions.first;
  }

  final List<double> activeTextSpanOpacities = <double>[];
  for (final RichText richText in tester.widgetList<RichText>(
    find.byType(RichText),
  )) {
    activeTextSpanOpacities.addAll(_activeTextSpanOpacities(richText.text));
  }
  if (activeTextSpanOpacities.isNotEmpty) {
    return activeTextSpanOpacities.first;
  }

  final List<double> settledOpacities = tester
      .widgetList<Opacity>(find.byType(Opacity))
      .map((Opacity widget) => widget.opacity)
      .where((double value) => value >= 1)
      .toList(growable: false);
  if (settledOpacities.isNotEmpty) {
    return 1;
  }

  return 0;
}

Future<Uint8List> _captureRawRgba(WidgetTester tester, Finder finder) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(finder);
  final Uint8List? pixels = await tester.runAsync<Uint8List>(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    image.dispose();
    return Uint8List.fromList(byteData!.buffer.asUint8List());
  });
  return pixels!;
}

List<double> _activeTextSpanOpacities(InlineSpan span) {
  final List<double> values = <double>[];
  if (span is TextSpan) {
    final Color? color = span.style?.color;
    if (color != null) {
      final double opacity = _colorOpacity(color);
      if (opacity > 0 && opacity < 1) {
        values.add(opacity);
      }
    }
    for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
      values.addAll(_activeTextSpanOpacities(child));
    }
  }
  return values;
}

double _colorOpacity(Color color) {
  final dynamic dynamicColor = color;
  try {
    return dynamicColor.a as double;
  } on NoSuchMethodError {
    return (dynamicColor.alpha as int) / 255;
  }
}

double _opacityByKey(WidgetTester tester, Key key) {
  return tester.widget<Opacity>(find.byKey(key)).opacity;
}

int _totalWidgetSpanCount(WidgetTester tester) {
  int total = 0;
  for (final RichText richText in tester.widgetList<RichText>(
    find.byType(RichText),
  )) {
    total += _widgetSpanCount(richText.text);
  }
  return total;
}

int _fadeInTokenHostCount(WidgetTester tester) {
  return find
      .byWidgetPredicate(
        (Widget widget) => widget.runtimeType.toString() == '_FadeInTokenHost',
      )
      .evaluate()
      .length;
}

Map<String, Rect> _rectsForTexts(WidgetTester tester, List<String> texts) {
  return <String, Rect>{
    for (final String text in texts) text: tester.getRect(find.text(text)),
  };
}

void _expectRectsClose(
  Map<String, Rect> actual,
  Map<String, Rect> expected, {
  double epsilon = 0.01,
}) {
  expect(actual.keys, expected.keys);
  for (final String text in expected.keys) {
    final Rect actualRect = actual[text]!;
    final Rect expectedRect = expected[text]!;
    expect(
      actualRect.left,
      moreOrLessEquals(expectedRect.left, epsilon: epsilon),
      reason: '$text left',
    );
    expect(
      actualRect.top,
      moreOrLessEquals(expectedRect.top, epsilon: epsilon),
      reason: '$text top',
    );
    expect(
      actualRect.width,
      moreOrLessEquals(expectedRect.width, epsilon: epsilon),
      reason: '$text width',
    );
    expect(
      actualRect.height,
      moreOrLessEquals(expectedRect.height, epsilon: epsilon),
      reason: '$text height',
    );
  }
}

int _inlineSelectionProxyCount(WidgetTester tester) {
  return find
      .byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_SelectableInlineTextProxy',
      )
      .evaluate()
      .length;
}

String _proxySelectedText(WidgetTester tester) {
  final StringBuffer selected = StringBuffer();
  for (final Element element in find
      .byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_SelectableInlineTextProxy',
      )
      .evaluate()) {
    final RenderObject? renderObject = element.renderObject;
    if (renderObject is Selectable) {
      final Selectable selectable = renderObject as Selectable;
      selected.write(selectable.getSelectedContent()?.plainText ?? '');
    }
  }
  return selected.toString();
}

int _widgetSpanCount(InlineSpan span) {
  if (span is WidgetSpan) {
    return 1;
  }
  if (span is TextSpan) {
    int total = 0;
    for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
      total += _widgetSpanCount(child);
    }
    return total;
  }
  return 0;
}

Future<void> _copySelection(WidgetTester tester) async {
  final BuildContext context = tester.element(find.byType(SelectableRegion));
  Actions.invoke(context, CopySelectionTextIntent.copy);
  await tester.pump();
}

RenderParagraph _renderParagraphContaining(
  WidgetTester tester,
  String plainText,
) {
  RenderParagraph? fallback;
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    if (!widget.text.toPlainText().contains(plainText)) {
      continue;
    }
    final RenderParagraph paragraph = element.renderObject! as RenderParagraph;
    if (widget.selectionRegistrar != null) {
      return paragraph;
    }
    fallback ??= paragraph;
  }
  if (fallback != null) {
    return fallback;
  }
  throw StateError('No RichText RenderParagraph contains "$plainText".');
}

ScrollPosition _horizontalScrollPosition(WidgetTester tester) {
  for (final ScrollableState state
      in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
    if (axisDirectionToAxis(state.position.axisDirection) == Axis.horizontal) {
      return state.position;
    }
  }
  throw StateError('No horizontal scroll position found.');
}

RenderParagraph _visibleTableParagraph(
  WidgetTester tester,
  Rect tableFrame, {
  required String contains,
}) {
  for (final Element element in find.byType(RichText).evaluate()) {
    final RichText widget = element.widget as RichText;
    if (!widget.text.toPlainText().contains(contains)) {
      continue;
    }
    final RenderParagraph paragraph = element.renderObject! as RenderParagraph;
    final Rect paragraphFrame =
        paragraph.localToGlobal(Offset.zero) & paragraph.size;
    if (tableFrame.contains(paragraphFrame.center)) {
      return paragraph;
    }
  }
  throw StateError(
    'No visible selectable table paragraph contains "$contains".',
  );
}

String _highlightedTextForColor(WidgetTester tester, Color color) {
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
    if (widget.selectionColor == color && paintRange != null) {
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

Offset _textOffsetToPosition(RenderParagraph paragraph, int offset) {
  const Rect caret = Rect.fromLTWH(0, 0, 2, 20);
  final Offset localOffset = paragraph.getOffsetForCaret(
    TextPosition(offset: offset),
    caret,
  );
  return paragraph.localToGlobal(localOffset);
}

Offset _textOffsetToHitPosition(
  RenderParagraph paragraph,
  int offset, {
  bool end = false,
}) {
  return _textOffsetToPosition(paragraph, offset) + Offset(end ? 4 : 2, 8);
}

Offset _textWidgetHitPosition(
  WidgetTester tester,
  String text, {
  bool end = false,
}) {
  final Rect textRect = tester.getRect(find.text(text));
  final Rect regionRect = tester.getRect(find.byType(SelectableRegion));
  final double rawX = end ? textRect.right + 4 : textRect.left + 1;
  final double x = rawX.clamp(regionRect.left + 1, regionRect.right - 1);
  return Offset(x, textRect.top + textRect.height / 2);
}

List<WidgetSpan> _allWidgetSpans(WidgetTester tester) {
  final List<WidgetSpan> spans = <WidgetSpan>[];
  for (final RichText richText in tester.widgetList<RichText>(
    find.byType(RichText),
  )) {
    spans.addAll(_widgetSpansIn(richText.text));
  }
  return spans;
}

List<WidgetSpan> _widgetSpansIn(InlineSpan span) {
  if (span is WidgetSpan) {
    return <WidgetSpan>[span];
  }
  final List<WidgetSpan> spans = <WidgetSpan>[];
  if (span is TextSpan) {
    for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
      spans.addAll(_widgetSpansIn(child));
    }
  }
  return spans;
}

Finder _footnoteLabel(String id) {
  return find.text('$id: ');
}

const String _gfmParserGoldenMarkdown = r'''
# GFM parser case 1

Streaming markdown case 1 mixes **strong**, _emphasis_, ~~deleted text~~, `inline | code`, an autolink https://example.com/1, and a reference link to [the docs][docs].

> GFM quote content keeps **inline markdown** intact.

- [x] completed task for case 1
- [ ] pending task with `inline | pipe`
- nested content continues after the task marker

| Feature | Value | Notes |
| --- | ---: | --- |
| Case | 1 | table row |
| Pipes | `a | b` | inline code cell |

Footnote reference[^case-1] before the code fence.

```dart
final value1 = 17;
debugPrint('case 1: $value1');
```

[^case-1]: Footnote body for parser case 1.

[docs]: https://pub.dev/packages/animated_streaming_markdown
''';

List<String> _nodeContentGolden(List<MarkdownRenderNode> nodes) {
  return nodes
      .map(
        (MarkdownRenderNode node) =>
            '${node.type}|content=${_compactGoldenText(node.content)}'
            '|raw=${_compactGoldenText(node.raw)}',
      )
      .toList(growable: false);
}

String _compactGoldenText(String value) {
  return value.replaceAll('\r', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
