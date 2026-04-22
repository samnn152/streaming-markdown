import 'package:flutter/material.dart';
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
              _renderNode(
                'Tap [OpenAI](https://openai.com) for details.',
              ),
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

    await tester.tapAt(tester.getCenter(find.text('OpenAI')));

    expect(tappedUrl, 'https://openai.com');
  });

  testWidgets('html tables use intrinsic columns', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[
              _renderNode(
                '''
<table>
  <tr><th>Column</th><th>Value</th></tr>
  <tr><td>HTML table</td><td>Rendered</td></tr>
</table>
''',
                type: 'html_block',
              ),
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

  testWidgets('html inline links are tappable', (
    WidgetTester tester,
  ) async {
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
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('[alpha]'), findsNothing);
    expect(find.text('Definition'), findsOneWidget);
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
  int startByte = 0,
}) {
  return MarkdownRenderNode(
    type: type,
    depth: 0,
    startByte: startByte,
    endByte: startByte + raw.length,
    startRow: 0,
    endRow: 0,
    raw: raw,
    content: raw,
  );
}
