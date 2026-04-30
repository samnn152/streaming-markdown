import 'dart:io';
import 'dart:math' as math;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _testFontFamily = 'Roboto';
const String _testMonoFontFamily = 'monospace';
const Duration _exampleTokenArrivalDelay = Duration(milliseconds: 350);
const Duration _exampleTokenFadeDuration = Duration(milliseconds: 1800);

void main() {
  setUpAll(() async {
    await _loadTestFont();
  });

  group('selection semantics unit', () {
    test('full block selection returns full raw markdown', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('paragraph', 'Prefix **bold** suffix', startByte: 0),
      ];

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: nodes,
        selectedPlainText: 'Prefix bold suffix',
      );

      expect(copied, 'Prefix **bold** suffix');
    });

    test('partial selection adds delimiters when cut through inline token', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('paragraph', 'Prefix [OpenAI](https://openai.com) suffix',
            startByte: 0),
      ];

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: nodes,
        selectedPlainText: 'penA',
      );

      expect(copied, '[penA](https://openai.com)');
    });

    test('partial inline formatting keeps semantic delimiters', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node(
          'paragraph',
          'Prefix **bold** _italic_ ~~strike~~ `code` suffix',
          startByte: 0,
        ),
      ];

      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'ol',
        ),
        '**ol**',
      );
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'tal',
        ),
        '_tal_',
      );
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'rik',
        ),
        '~~rik~~',
      );
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'od',
        ),
        '`od`',
      );
    });

    test('partial inline formatting respects block edge delimiter rules', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('paragraph', '**bold**', startByte: 0),
      ];

      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'bo',
        ),
        'bo**',
      );
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'ld',
        ),
        '**ld',
      );
    });

    test('full selection returns full raw markdown for every core block', () {
      final Map<MarkdownRenderNode, String> cases =
          <MarkdownRenderNode, String>{
        _node('atx_heading', '# Heading', startByte: 0, content: 'Heading'):
            'Heading',
        _node('paragraph', 'Text **bold**', startByte: 20): 'Text bold',
        _node('list', '- one\n- two', startByte: 40): 'one\ntwo',
        _node('block_quote', '> quote', startByte: 60): 'quote',
        _node('fenced_code_block', '```dart\nprint(1);\n```', startByte: 80):
            'print(1);',
        _node('thematic_break', '---', startByte: 110): '',
      };

      for (final MapEntry<MarkdownRenderNode, String> entry in cases.entries) {
        expect(
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
            nodes: <MarkdownRenderNode>[entry.key],
            selectedPlainText: entry.value,
          ),
          entry.key.raw,
        );
      }
    });

    test('partial list quote and code selections keep markdown semantics', () {
      final List<MarkdownRenderNode> listNodes = <MarkdownRenderNode>[
        _node('list', '- one\n- **two**\n1. three', startByte: 0),
      ];
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: listNodes,
          selectedPlainText: 'one\ntw',
        ),
        '- one\n- tw**',
      );

      final List<MarkdownRenderNode> quoteNodes = <MarkdownRenderNode>[
        _node('block_quote', '> first\n> second', startByte: 0),
      ];
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: quoteNodes,
          selectedPlainText: 'first\nsec',
        ),
        '> first\n> sec',
      );

      final List<MarkdownRenderNode> codeNodes = <MarkdownRenderNode>[
        _node(
          'fenced_code_block',
          '```dart\nfinal a = 1;\nprint(a);\n```',
          startByte: 0,
        ),
      ];
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: codeNodes,
          selectedPlainText: 'print(a);',
        ),
        '```dart\nprint(a);\n```',
      );
    });

    test('partial inline link edge selections remain deterministic', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('paragraph', '[docs](https://docs.flutter.dev)', startByte: 0),
      ];

      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'do',
        ),
        '[do](https://docs.flutter.dev)',
      );
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'cs',
        ),
        '[cs](https://docs.flutter.dev)',
      );
    });

    test('multi-block selection is joined with double newlines', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('atx_heading', '# H1', startByte: 0, content: 'H1'),
        _node('paragraph', 'Body paragraph', startByte: 5),
        _node('thematic_break', '---', startByte: 20),
      ];

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: nodes,
        selectedPlainText: 'H1\n\nBody paragraph',
      );

      expect(copied, '# H1\n\nBody paragraph');
    });

    test('table selection maps flattened cell text back to markdown table', () {
      const String firstTable = '| Case | Markdown | Rendered behavior |\n'
          '| :--- | :------: | ---------------: |\n'
          '| Inline code | `a | b` | Keeps pipe inside code |\n'
          r'| Escaped pipe | `a \| b` | Keeps escaped separator |'
          '\n| Link | [docs](https://docs.flutter.dev) | '
          'Tappable cell content |';
      const String secondTable = '| Name | Status | Notes |\n'
          '| --- | --- | --- |\n'
          '| Alpha | Ready | Basic cells |\n'
          '| Beta | Streaming | **Formatted** cell |';
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('atx_heading', '# Tables',
            startByte: 0, startRow: 0, content: 'Tables'),
        _node('pipe_table_header', '| Case | Markdown | Rendered behavior |',
            startByte: 10, startRow: 2),
        _node(
          'pipe_table_delimiter_row',
          '| :--- | :------: | ---------------: |',
          startByte: 49,
          startRow: 3,
        ),
        _node(
          'pipe_table_row',
          '| Inline code | `a | b` | Keeps pipe inside code |',
          startByte: 88,
          startRow: 4,
        ),
        _node(
          'pipe_table_row',
          r'| Escaped pipe | `a \| b` | Keeps escaped separator |',
          startByte: 141,
          startRow: 5,
        ),
        _node(
          'pipe_table_row',
          '| Link | [docs](https://docs.flutter.dev) | '
              'Tappable cell content |',
          startByte: 197,
          startRow: 6,
        ),
        _node('pipe_table_header', '| Name | Status | Notes |',
            startByte: 266, startRow: 8),
        _node('pipe_table_delimiter_row', '| --- | --- | --- |',
            startByte: 291, startRow: 9),
        _node('pipe_table_row', '| Alpha | Ready | Basic cells |',
            startByte: 309, startRow: 10),
        _node(
          'pipe_table_row',
          '| Beta | Streaming | **Formatted** cell |',
          startByte: 339,
          startRow: 11,
        ),
      ];

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: nodes,
        selectedPlainText: 'Tables'
            'CaseMarkdownRendered behavior'
            'Inline codea | bKeeps pipe inside code'
            'Escaped pipea | bKeeps escaped separator'
            'LinkdocsTappable cell content'
            'NameStatusNotes'
            'AlphaReadyBasic cells'
            'BetaStreamingFormatted cell',
      );

      expect(copied, '# Tables\n\n$firstTable\n\n$secondTable');
    });

    test('partial table selection stops at selected cell boundary', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('pipe_table_header', '| Name | Status | Notes |',
            startByte: 0, startRow: 0),
        _node('pipe_table_delimiter_row', '| --- | --- | --- |',
            startByte: 25, startRow: 1),
        _node('pipe_table_row', '| Alpha | Ready | Basic cells |',
            startByte: 43, startRow: 2),
        _node(
          'pipe_table_row',
          '| Beta | Streaming | **Formatted** cell |',
          startByte: 74,
          startRow: 3,
        ),
      ];

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: nodes,
        selectedPlainText: 'NameStatusNotesAlphaReady',
      );

      expect(
        copied,
        '| Name | Status | Notes |\n'
        '| --- | --- | --- |\n'
        '| Alpha | Ready |  |',
      );
      expect(copied, isNot(contains('Basic cells')));
      expect(copied, isNot(contains('Beta')));
    });

    test('partial table selection supports cell-only and formatted cells', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('pipe_table_header', '| Name | Status | Notes |',
            startByte: 0, startRow: 0),
        _node('pipe_table_delimiter_row', '| --- | --- | --- |',
            startByte: 25, startRow: 1),
        _node('pipe_table_row', '| Alpha | Ready | Basic cells |',
            startByte: 43, startRow: 2),
        _node(
          'pipe_table_row',
          '| Beta | Streaming | **Formatted** cell |',
          startByte: 74,
          startRow: 3,
        ),
      ];

      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'Ready',
        ),
        '| Status |\n'
        '| --- |\n'
        '| Ready |',
      );
      expect(
        StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
          nodes: nodes,
          selectedPlainText: 'StreamingForm',
        ),
        '| Status | Notes |\n'
        '| --- | --- |\n'
        '| Streaming | Form** |',
      );
    });

    test('multi-block selection preserves list quote and code markdown', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('list', '- one\n- two', startByte: 0),
        _node('block_quote', '> quoted', startByte: 12),
        _node('fenced_code_block', '```dart\nprint(1);\n```', startByte: 22),
      ];

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: nodes,
        selectedPlainText: 'one\ntwo\n\nquoted\n\nprint(1);',
      );

      expect(
        copied,
        '- one\n- two\n\n> quoted\n\n```dart\nprint(1);\n```',
      );
    });

    test('empty block can still be preserved in copy output', () {
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
        _node('paragraph', 'A', startByte: 0),
        _node('thematic_break', '---', startByte: 1),
        _node('paragraph', 'B', startByte: 4),
      ];

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: nodes,
        selectedPlainText: 'A\n\n\n\nB',
      );

      expect(copied, 'A\n\n---\n\nB');
    });

    test('copied full blocks are render-idempotent after markdown reparse', () {
      const String input = '# T\n\n'
          'A [link](https://example.com)\n\n'
          '- x\n'
          '- y\n\n'
          '```dart\n'
          'print(1);\n'
          '```';
      final List<MarkdownRenderNode> inputNodes =
          _parseRenderNodesFromMarkdown(input);

      final String copied =
          StreamingMarkdownRenderView.debugMarkdownForSelectedPlainText(
        nodes: inputNodes,
        selectedPlainText: 'T\n\nA link\n\n- x\n- y\n\n```dart\nprint(1);\n```',
      );
      final List<MarkdownRenderNode> outputNodes =
          _parseRenderNodesFromMarkdown(copied);

      expect(_renderSignatures(outputNodes), _renderSignatures(inputNodes));
    });
  });

  group('selection integration/widget', () {
    testWidgets('custom builder keeps selection area active', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _testApp(
          Scaffold(
            body: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[
                _node('paragraph', 'Prefix **bold** suffix', startByte: 0),
                _node('list', '- one\n- two', startByte: 24),
                _node('fenced_code_block', '```dart\nprint(1);\n```',
                    startByte: 36),
                _node('block_quote', '> quote', startByte: 58),
              ],
              enableTextSelection: true,
              tokenFadeInDuration: Duration.zero,
              customBlockBuilder: (
                BuildContext context,
                StreamingMarkdownBlockBuildContext block,
              ) {
                if (block.node.type == 'paragraph') {
                  return DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0x1100AA00)),
                    child: block.defaultWidget,
                  );
                }
                return null;
              },
            ),
          ),
        ),
      );

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(SelectableRegion), findsOneWidget);
      expect(find.textContaining('Prefix'), findsOneWidget);
    });

    testWidgets('pixel parity smoke: same render size with/without selection', (
      WidgetTester tester,
    ) async {
      Future<void> pump(bool enableSelection) {
        return tester.pumpWidget(
          _testApp(
            Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: <MarkdownRenderNode>[
                  _node('atx_heading', '# Title',
                      startByte: 0, content: 'Title'),
                  _node('paragraph', 'Paragraph with **bold** text.',
                      startByte: 7),
                  _node('list', '- a\n- b', startByte: 37),
                ],
                enableTextSelection: enableSelection,
                tokenFadeInDuration: Duration.zero,
              ),
            ),
          ),
        );
      }

      await pump(false);
      await tester.pumpAndSettle();
      final Size sizeOff =
          tester.getSize(find.byType(StreamingMarkdownRenderView));

      await pump(true);
      await tester.pumpAndSettle();
      final Size sizeOn =
          tester.getSize(find.byType(StreamingMarkdownRenderView));

      expect(sizeOn, sizeOff);
    });
  });

  group('golden snapshots', () {
    testWidgets('selection disabled snapshot', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _testApp(
          RepaintBoundary(
            key: const ValueKey<String>('golden-root-disabled'),
            child: Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: <MarkdownRenderNode>[
                  _node('atx_heading', '# Golden Title',
                      startByte: 0, content: 'Golden Title'),
                  _node('paragraph', 'Body with **bold** and _italic_.',
                      startByte: 15),
                  _node('list', '- first\n- second', startByte: 48),
                ],
                enableTextSelection: false,
                tokenFadeInDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey<String>('golden-root-disabled')),
        matchesGoldenFile('goldens/selection_disabled.png'),
      );
    });

    testWidgets('selection enabled snapshot', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _testApp(
          RepaintBoundary(
            key: const ValueKey<String>('golden-root-enabled'),
            child: Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: <MarkdownRenderNode>[
                  _node('atx_heading', '# Golden Title',
                      startByte: 0, content: 'Golden Title'),
                  _node('paragraph', 'Body with **bold** and _italic_.',
                      startByte: 15),
                  _node('list', '- first\n- second', startByte: 48),
                ],
                enableTextSelection: true,
                tokenFadeInDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey<String>('golden-root-enabled')),
        matchesGoldenFile('goldens/selection_enabled.png'),
      );
    });

    testWidgets('all supported markdown blocks snapshot',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _testApp(
          RepaintBoundary(
            key: const ValueKey<String>('golden-all-blocks'),
            child: Scaffold(
              body: StreamingMarkdownRenderView(
                padding: const EdgeInsets.all(16),
                tokenFadeInDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                markdownTheme: _goldenMarkdownTheme,
                nodes: _allSupportedBlockNodes(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey<String>('golden-all-blocks')),
        matchesGoldenFile('goldens/all_supported_blocks.png'),
      );
    });
  });

  group('golden animation timeline', () {
    testWidgets('fade animation snapshots at 1.5 animation and settled',
        (WidgetTester tester) async {
      await _pumpAnimationGolden(
        tester,
        keyPrefix: 'fade',
        animationBuilder: _fadeBuilder,
        goldenPrefix: 'goldens/anim_fade',
      );
    });

    testWidgets('glitch animation snapshots at 1.5 animation and settled',
        (WidgetTester tester) async {
      await _pumpAnimationGolden(
        tester,
        keyPrefix: 'glitch',
        animationBuilder: _glitchBuilder,
        goldenPrefix: 'goldens/anim_glitch',
      );
    });
  });
}

Future<void> _pumpAnimationGolden(
  WidgetTester tester, {
  required String keyPrefix,
  required StreamingMarkdownTokenAnimationBuilder animationBuilder,
  required String goldenPrefix,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final List<MarkdownRenderNode> settledFirstToken = _animationNodes(
    includeHalfToken: false,
  );
  final List<MarkdownRenderNode> midOnePointFiveTokens = _animationNodes(
    includeHalfToken: true,
  );

  Future<void> pumpFrame(String key, List<MarkdownRenderNode> nodes) async {
    await tester.pumpWidget(
      _testApp(
        RepaintBoundary(
          key: ValueKey<String>(key),
          child: Scaffold(
            body: StreamingMarkdownRenderView(
              nodes: nodes,
              padding: const EdgeInsets.all(16),
              tokenArrivalDelay: _exampleTokenArrivalDelay,
              tokenFadeInDuration: _exampleTokenFadeDuration,
              tokenAnimationBuilder: animationBuilder,
              allowUnclosedInlineDelimiters: true,
              markdownTheme: _goldenMarkdownTheme,
            ),
          ),
        ),
      ),
    );
  }

  await pumpFrame('anim-$keyPrefix', settledFirstToken);
  await tester.pumpAndSettle();
  await pumpFrame('anim-$keyPrefix', midOnePointFiveTokens);
  await tester.pump(_exampleTokenFadeDuration ~/ 2);
  await expectLater(
    find.byKey(ValueKey<String>('anim-$keyPrefix')),
    matchesGoldenFile('${goldenPrefix}_mid_1_5.png'),
  );

  await tester.pumpAndSettle(const Duration(seconds: 20));
  await expectLater(
    find.byKey(ValueKey<String>('anim-$keyPrefix')),
    matchesGoldenFile('${goldenPrefix}_settled.png'),
  );
}

List<MarkdownRenderNode> _allSupportedBlockNodes() {
  int start = 0;
  MarkdownRenderNode add(String type, String raw, {String? content}) {
    final MarkdownRenderNode node = _node(
      type,
      raw,
      startByte: start,
      content: content,
    );
    start += raw.length + 2;
    return node;
  }

  return <MarkdownRenderNode>[
    add('front_matter', '---\ntitle: Demo\ntags: [a, b]\n---'),
    add('atx_heading', '# Heading One', content: 'Heading One'),
    add('setext_heading', 'Setext Heading\n=============',
        content: 'Setext Heading'),
    add('paragraph',
        'Paragraph with **bold**, _italic_, and [link](https://example.com).'),
    add('list', '- item one\n- item two\n- [ ] unchecked\n- [x] checked'),
    add('block_quote', '> Quoted line one\n> Quoted line two'),
    add('fenced_code_block', '```dart\nvoid main() {\n  print("hi");\n}\n```'),
    add('indented_code_block', '    final a = 1;\n    final b = a + 1;'),
    add('thematic_break', '---', content: ''),
    add('html_block', '<p>Inline <strong>HTML</strong> block.</p>'),
    add('pipe_table', '| A | B |\n| --- | --- |\n| 1 | 2 |'),
    add('table', '| C | D |\n| --- | --- |\n| 3 | 4 |'),
    add('pipe_table_header', '| E | F |', content: '| E | F |'),
    add('pipe_table_row', '| 5 | 6 |', content: '| 5 | 6 |'),
    add('pipe_table_delimiter_row', '| --- | --- |', content: ''),
    add('footnote_definition', '[^a]: Footnote body for a.'),
    add('link_reference_definition',
        '[repo]: https://github.com/samnn152/streaming-markdown'),
  ];
}

List<MarkdownRenderNode> _animationNodes({required bool includeHalfToken}) {
  int start = 0;
  MarkdownRenderNode add(String type, String raw, {String? content}) {
    final MarkdownRenderNode node = _node(
      type,
      raw,
      startByte: start,
      content: content,
    );
    start += raw.length + 2;
    return node;
  }

  final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
    add('atx_heading', '# First token settled', content: 'First token settled'),
  ];
  if (includeHalfToken) {
    nodes.add(
      add(
        'paragraph',
        'Second token is halfway through the example fade duration.',
      ),
    );
  }
  return nodes;
}

Widget _fadeBuilder(
    BuildContext context, StreamingMarkdownAnimatedToken token) {
  return Opacity(opacity: token.value, child: token.child);
}

Widget _glitchBuilder(
    BuildContext context, StreamingMarkdownAnimatedToken token) {
  final double t = token.value;
  final double shakeX = math.sin(t * math.pi * 22) * (1 - t) * 4.0;
  final double shakeY = math.cos(t * math.pi * 18) * (1 - t) * 2.0;
  return Opacity(
    opacity: Curves.easeOut.transform(t),
    child: Transform.translate(
      offset: Offset(shakeX, shakeY),
      child: Transform.scale(
        scale: 0.92 + (0.08 * Curves.easeOutBack.transform(t)),
        alignment: Alignment.bottomLeft,
        child: token.child,
      ),
    ),
  );
}

const StreamingMarkdownThemeData _goldenMarkdownTheme =
    StreamingMarkdownThemeData(
  blockSpacing: 16,
  quoteBackgroundColor: Color(0x111F7A68),
  codeBlockBackgroundColor: Color(0xFF0F172A),
  codeBlockHeaderBackgroundColor: Color(0xFF1E293B),
  metadataBackgroundColor: Color(0xFFF8FAFC),
  metadataBorderColor: Color(0xFFCBD5E1),
  metadataTextStyle: TextStyle(
    color: Color(0xFF334155),
    fontFamily: _testMonoFontFamily,
    fontSize: 12,
  ),
  thematicBreakColor: Color(0xFF94A3B8),
  imageErrorBackgroundColor: Color(0xFFE2E8F0),
  imageErrorTextStyle: TextStyle(color: Color(0xFF334155)),
  selectionColor: Color(0x5538BDF8),
);

MaterialApp _testApp(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: _testFontFamily),
    home: child,
  );
}

Future<void> _loadTestFont() async {
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final String regularPath = await _findFlutterFont(
    flutterRoot,
    'Roboto-Regular.ttf',
  );
  final String boldPath =
      await _findFlutterFont(flutterRoot, 'Roboto-Bold.ttf');
  final String italicPath = await _findFlutterFont(
    flutterRoot,
    'Roboto-Italic.ttf',
  );
  final String boldItalicPath = await _findFlutterFont(
    flutterRoot,
    'Roboto-BoldItalic.ttf',
  );

  await _loadFontFamily(_testFontFamily, <String>[
    regularPath,
    boldPath,
    italicPath,
    boldItalicPath,
  ]);
  await _loadFontFamily(_testMonoFontFamily, <String>[
    regularPath,
    boldPath,
    italicPath,
    boldItalicPath,
  ]);
}

Future<String> _findFlutterFont(String? flutterRoot, String fileName) async {
  final List<String> candidates = <String>[
    if (flutterRoot != null && flutterRoot.isNotEmpty)
      '$flutterRoot/bin/cache/artifacts/material_fonts/$fileName',
    '/Users/hider152/sdk/flutter/bin/cache/artifacts/material_fonts/$fileName',
  ];
  for (final String path in candidates) {
    final File candidate = File(path);
    if (await candidate.exists()) {
      return path;
    }
  }
  throw StateError('$fileName not found in Flutter SDK cache.');
}

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final FontLoader loader = FontLoader(family);
  for (final String path in paths) {
    final Uint8List bytes = await File(path).readAsBytes();
    loader.addFont(
      Future<ByteData>.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  }
  await loader.load();
}

List<MarkdownRenderNode> _parseRenderNodesFromMarkdown(String markdown) {
  final MarkdownDocument document =
      const RopeMarkdownParser().parse(RopeString()..append(markdown));
  return document.blocks.map((MarkdownBlockNode block) {
    final String raw = markdown.substring(block.start, block.end).trimRight();
    if (block is HeadingNode) {
      return _node(
        'atx_heading',
        raw,
        startByte: block.start,
        content: block.text,
      );
    }
    if (block is ParagraphNode) {
      return _node('paragraph', raw, startByte: block.start);
    }
    if (block is ListNode) {
      return _node('list', raw, startByte: block.start);
    }
    if (block is CodeFenceNode) {
      return _node('fenced_code_block', raw, startByte: block.start);
    }
    return _node('paragraph', raw, startByte: block.start);
  }).toList(growable: false);
}

List<String> _renderSignatures(List<MarkdownRenderNode> nodes) {
  return nodes.map((MarkdownRenderNode node) {
    return '${node.type}:${node.raw.trimRight()}';
  }).toList(growable: false);
}

MarkdownRenderNode _node(
  String type,
  String raw, {
  required int startByte,
  int startRow = 0,
  int? endRow,
  String? content,
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
