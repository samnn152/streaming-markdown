import 'dart:io';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _testFontFamily = 'Roboto';
const String _testMonoFontFamily = 'monospace';
const Size _goldenSize = Size(520, 100);
const List<int> _milestones = <int>[2, 4, 6, 8];
const Color _selectionPaint = Color(0x5538BDF8);
const ValueKey<String> _scrollKey = ValueKey<String>('stream-scroll-viewport');

void main() {
  setUpAll(() async {
    await _loadTestFont();
  });

  group('streaming scroll golden snapshots', () {
    for (final _StreamingScrollGoldenCase scenario in _streamingScrollCases) {
      testWidgets('${scenario.slug} keeps first block selected while streaming',
          (WidgetTester tester) async {
        await _pumpStreamingScrollGolden(tester, scenario);
      });
    }
  }, skip: !Platform.isMacOS || Platform.environment['SKIP_GOLDENS'] == 'true');
}

Future<void> _pumpStreamingScrollGolden(
  WidgetTester tester,
  _StreamingScrollGoldenCase scenario,
) async {
  await tester.binding.setSurfaceSize(_goldenSize);
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

  String currentMarkdown = scenario.markdownForSecond(0);
  late StateSetter updateHost;

  await tester.pumpWidget(
    _testApp(
      RepaintBoundary(
        key: ValueKey<String>('stream-scroll-${scenario.slug}'),
        child: SizedBox(
          width: _goldenSize.width,
          height: _goldenSize.height,
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return SingleChildScrollView(
                key: _scrollKey,
                controller: scrollController,
                child: AnimatedStreamingMarkdown.fromMarkdown(
                  markdown: currentMarkdown,
                  padding: const EdgeInsets.all(8),
                  allowIncompleteInlineSyntax: true,
                  tokenStaggerDelay: const Duration(milliseconds: 90),
                  tokenAnimationDuration: const Duration(milliseconds: 500),
                  tokenAnimationCurve: Curves.easeOut,
                  tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                  enableSelection: true,
                  selectionStrategy: SelectionStrategy.raw,
                  theme: _goldenMarkdownTheme,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  // Select a settled anchor so snapshots measure drift during later streaming,
  // not the initial token fade timing of the selected block itself.
  await tester.pumpAndSettle(const Duration(milliseconds: 50));

  final SelectableRegionState regionState =
      tester.state<SelectableRegionState>(find.byType(SelectableRegion));
  regionState.selectAll(SelectionChangedCause.keyboard);
  await tester.pump();
  await _copySelection(tester);
  expect(clipboardText, scenario.blocks.first);

  for (final int second in _milestones) {
    updateHost(() {
      currentMarkdown = scenario.markdownForSecond(second);
    });
    await tester.pump(const Duration(seconds: 2));
    await _dragThenJumpToScrollOffset(
      tester,
      scrollController,
      scenario.scrollOffsetForSecond(second),
    );

    await _copySelection(tester);
    expect(
      clipboardText,
      scenario.blocks.first,
      reason: '${scenario.slug} at ${second}s must copy the absolute first '
          'markdown block after streaming and scrolling.',
    );

    await expectLater(
      find.byKey(ValueKey<String>('stream-scroll-${scenario.slug}')),
      matchesGoldenFile(
        'goldens/stream_scroll_${scenario.slug}_${second}s.png',
      ),
    );
  }
}

Future<void> _copySelection(WidgetTester tester) async {
  final BuildContext context = tester.element(find.byType(RichText).first);
  Actions.invoke(context, CopySelectionTextIntent.copy);
  await tester.pump();
}

Future<void> _dragThenJumpToScrollOffset(
  WidgetTester tester,
  ScrollController controller,
  double requestedOffset,
) async {
  if (!controller.hasClients) {
    return;
  }
  final ScrollPosition position = controller.position;
  final double offset = requestedOffset.clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  final double delta = offset - position.pixels;
  if (delta.abs() > 0.5) {
    await tester.drag(
      find.byKey(_scrollKey),
      Offset(0, -delta),
      touchSlopY: 0,
    );
    await tester.pump();
  }
  controller.jumpTo(offset);
  await tester.pump();
}

class _StreamingScrollGoldenCase {
  const _StreamingScrollGoldenCase({
    required this.slug,
    required this.blocks,
    required this.scrollOffsets,
  });

  final String slug;
  final List<String> blocks;
  final List<double> scrollOffsets;

  String markdownForSecond(int second) {
    final int visibleBlocks = switch (second) {
      <= 0 => 1,
      2 => 2,
      4 => 4,
      6 => 6,
      _ => blocks.length,
    };
    final int clampedBlocks = visibleBlocks < 1
        ? 1
        : visibleBlocks > blocks.length
            ? blocks.length
            : visibleBlocks;
    return blocks.take(clampedBlocks).join('\n\n');
  }

  double scrollOffsetForSecond(int second) {
    final int rawIndex = _milestones.indexOf(second);
    final int index = rawIndex < 0
        ? 0
        : rawIndex >= scrollOffsets.length
            ? scrollOffsets.length - 1
            : rawIndex;
    return scrollOffsets[index];
  }
}

const List<_StreamingScrollGoldenCase> _streamingScrollCases =
    <_StreamingScrollGoldenCase>[
  _StreamingScrollGoldenCase(
    slug: 'paragraph_emphasis',
    scrollOffsets: <double>[0, 8, 16, 24],
    blocks: <String>[
      'Selected anchor block with **bold** and _italic_ text.',
      'A streamed paragraph arrives below the selection.',
      'Another sentence keeps wrapping inside the 100px viewport.',
      '- first streamed bullet\n- second streamed bullet',
      '> A quote appears while the scroll position changes.',
      '`inline code` and a [link](https://example.com) finish the case.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'heading_intro',
    scrollOffsets: <double>[0, 6, 14, 22],
    blocks: <String>[
      '# Selected Heading',
      'Intro text streams under the selected heading.',
      '## Secondary heading',
      'More markdown arrives as the viewport scrolls.',
      '- scan\n- compare\n- copy',
      'Final paragraph with **strong** emphasis.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'task_list',
    scrollOffsets: <double>[0, 10, 18, 28],
    blocks: <String>[
      'Selected task summary block stays the anchor.',
      '- [x] Parsed first chunk\n- [ ] Rendering next chunk',
      '- [ ] Scroll while appending\n- [x] Keep source range stable',
      'Follow-up paragraph after the task list.',
      '> Status remains readable during movement.',
      'Done marker at the tail.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'blockquote',
    scrollOffsets: <double>[0, 9, 18, 27],
    blocks: <String>[
      'Selected context before the quoted stream.',
      '> The streamed quote starts here.\n> It wraps across lines.',
      '> Another quoted line arrives later.',
      'A normal paragraph follows the quote.',
      '- quote note\n- scroll note',
      'Closing paragraph.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'fenced_code',
    scrollOffsets: <double>[0, 12, 24, 36],
    blocks: <String>[
      'Selected explanation before the code block.',
      '```dart\nfinal value = 42;\n```',
      'The code block has settled, but text keeps streaming.',
      r'```dart'
          '\n'
          r'String greet(String name) => "Hi $name";'
          '\n'
          r'```',
      '- compiler note\n- formatter note',
      'End of the code case.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'table',
    scrollOffsets: <double>[0, 12, 24, 34],
    blocks: <String>[
      'Selected table introduction block.',
      '| Name | Status |\n| --- | --- |\n| Alpha | Ready |',
      '| Name | Status |\n| --- | --- |\n| Beta | Streaming |',
      'Table text keeps appending while scroll moves.',
      '| Metric | Value |\n| --- | ---: |\n| FPS | 60 |',
      'Table case complete.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'footnotes',
    scrollOffsets: <double>[0, 10, 20, 32],
    blocks: <String>[
      'Selected footnote lead block.',
      'Inline reference arrives here.[^parser]',
      'Another reference follows.[^render]',
      '[^parser]: Parser emits footnote nodes.',
      '[^render]: Renderer groups definitions compactly.',
      'Footnote section complete.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'latex',
    scrollOffsets: <double>[0, 8, 16, 26],
    blocks: <String>[
      'Selected math preface block.',
      r'Inline math $a^2 + b^2 = c^2$ appears.',
      r'$$\int_0^1 x^2 dx = \frac{1}{3}$$',
      'Text after display math keeps streaming.',
      r'| Symbol | Meaning |'
          '\n'
          r'| --- | --- |'
          '\n'
          r'| $x$ | input |',
      'Math case complete.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'html_block',
    scrollOffsets: <double>[0, 10, 20, 30],
    blocks: <String>[
      'Selected HTML preface block.',
      '<section>\n  <h2>Streaming HTML</h2>\n</section>',
      'Markdown resumes after the HTML block.',
      '- raw block\n- rendered block',
      '<aside>Compact inline HTML note.</aside>',
      'HTML case complete.',
    ],
  ),
  _StreamingScrollGoldenCase(
    slug: 'mixed_response',
    scrollOffsets: <double>[0, 12, 24, 36],
    blocks: <String>[
      'Selected mixed response opening block.',
      'A paragraph with **bold**, _italic_, and `code`.',
      '- item one\n- item two',
      '> A quoted observation while content streams.',
      '```text\nstable source range\n```',
      '| Phase | Time |\n| --- | ---: |\n| Final | 8s |',
    ],
  ),
];

const StreamingMarkdownThemeData _goldenMarkdownTheme =
    StreamingMarkdownThemeData(
  blockSpacing: 10,
  paragraphTextStyle: TextStyle(
    color: Color(0xFF111827),
    fontSize: 13,
    height: 1.25,
  ),
  heading1TextStyle: TextStyle(
    color: Color(0xFF111827),
    fontSize: 18,
    height: 1.15,
    fontWeight: FontWeight.w700,
  ),
  heading2TextStyle: TextStyle(
    color: Color(0xFF111827),
    fontSize: 16,
    height: 1.15,
    fontWeight: FontWeight.w700,
  ),
  inlineCodeBackgroundColor: Color(0xFFEFF6FF),
  inlineCodeTextStyle: TextStyle(
    color: Color(0xFF1D4ED8),
    fontFamily: _testMonoFontFamily,
    fontSize: 12,
  ),
  codeBlockBackgroundColor: Color(0xFF0F172A),
  codeBlockHeaderBackgroundColor: Color(0xFF1E293B),
  codeBlockTextStyle: TextStyle(
    color: Color(0xFFE2E8F0),
    fontFamily: _testMonoFontFamily,
    fontSize: 12,
    height: 1.3,
  ),
  codeBlockLanguageTextStyle: TextStyle(
    color: Color(0xFFCBD5E1),
    fontSize: 11,
    fontWeight: FontWeight.w700,
  ),
  quoteBackgroundColor: Color(0xFFEFF6FF),
  tableBorderColor: Color(0xFFCBD5E1),
  tableHeaderBackgroundColor: Color(0xFFEFF6FF),
  metadataBackgroundColor: Color(0xFFF8FAFC),
  metadataBorderColor: Color(0xFFCBD5E1),
  thematicBreakColor: Color(0xFF94A3B8),
  selectionColor: _selectionPaint,
);

MaterialApp _testApp(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: _testFontFamily),
    home: Scaffold(
      backgroundColor: Colors.white,
      body: ColoredBox(color: Colors.white, child: child),
    ),
  );
}

Future<void> _loadTestFont() async {
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final String regularPath = await _findFlutterFont(
    flutterRoot,
    'Roboto-Regular.ttf',
  );
  final String boldPath = await _findFlutterFont(
    flutterRoot,
    'Roboto-Bold.ttf',
  );
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
