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
}

Set<String> _collectTypes(MarkdownSyntaxNode node) {
  final Set<String> out = <String>{node.type};
  for (final MarkdownSyntaxNode child in node.children) {
    out.addAll(_collectTypes(child));
  }
  return out;
}
