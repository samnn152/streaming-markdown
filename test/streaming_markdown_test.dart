import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';

void main() {
  test('library name is stable', () {
    expect(streamingMarkdownLibraryName, 'animated_streaming_markdown');
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

    final Iterable<RichText> candidates =
        tester.widgetList<RichText>(find.byType(RichText)).where(
              (RichText widget) => widget.text.toPlainText().contains('OpenAI'),
            );
    TapGestureRecognizer? recognizer;
    for (final RichText widget in candidates) {
      recognizer = _findRecognizerForText(widget.text, 'OpenAI');
      if (recognizer != null) {
        break;
      }
    }
    recognizer?.onTap?.call();

    expect(tappedUrl, 'https://openai.com');
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
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final BuildContext context = tester.element(
      find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('Inline OpenAI link.'),
          )
          .first,
    );
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

    expect(clipboardText, 'Inline [OpenAI](https://openai.com) link.');
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
            tokenFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );

    final SelectableRegionState regionState =
        tester.state<SelectableRegionState>(find.byType(SelectableRegion));
    regionState.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final BuildContext context = tester.element(
      find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is RichText &&
                widget.text.toPlainText().contains('Front matter'),
          )
          .first,
    );
    Actions.invoke(context, CopySelectionTextIntent.copy);
    await tester.pump();

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

      expect(afterResize, greaterThan(beforeResize - 0.2));
      expect(afterSelectionToggle, greaterThan(beforeResize - 0.2));
    },
  );

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
                body: SelectionArea(
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
    expect(find.byType(Table), findsOneWidget);
    expect(
      tester.getSize(find.byType(Table)).height,
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

    expect((checkboxCenter.dy - textCenter.dy).abs(), lessThanOrEqualTo(2));
  });
}

Set<String> _collectTypes(MarkdownSyntaxNode node) {
  final Set<String> out = <String>{node.type};
  for (final MarkdownSyntaxNode child in node.children) {
    out.addAll(_collectTypes(child));
  }
  return out;
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

TapGestureRecognizer? _findRecognizerForText(InlineSpan span, String target) {
  if (span is TextSpan) {
    if (span.text == target && span.recognizer is TapGestureRecognizer) {
      return span.recognizer! as TapGestureRecognizer;
    }
    for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
      final TapGestureRecognizer? recognizer = _findRecognizerForText(
        child,
        target,
      );
      if (recognizer != null) {
        return recognizer;
      }
    }
  }
  return null;
}

double _activeTokenOpacity(WidgetTester tester) {
  final List<double> activeOpacities = tester
      .widgetList<Opacity>(find.byType(Opacity))
      .map((Opacity widget) => widget.opacity)
      .where((double value) => value > 0 && value < 1)
      .toList(growable: false);
  expect(activeOpacities, isNotEmpty);
  return activeOpacities.first;
}

Finder _footnoteLabel(String id) {
  return find.text('$id: ');
}
