import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stress parse handles large markdown payload', () async {
    final StreamingMarkdownParseWorker worker = StreamingMarkdownParseWorker();
    await worker.start();

    try {
      final String markdown = _buildStressMarkdown(
        sections: 220,
        listItemsPerSection: 6,
        paragraphRepeats: 5,
      );

      final Stopwatch sw = Stopwatch()..start();
      final StreamingMarkdownParseResult result = await worker.request(
        op: 'set',
        text: markdown,
        includeNodes: true,
      );
      sw.stop();

      expect(result.basicBlockCount, greaterThan(900));
      if (result.nativeAvailable) {
        expect(result.renderNodes.length, greaterThan(900));
      }
      expect(result.totalTime.inMicroseconds, greaterThan(0));

      // Keep metrics visible in test logs for manual perf tracking over time.
      // ignore: avoid_print
      print(
        'stress-parse bytes=${markdown.length} '
        'blocks=${result.basicBlockCount} '
        'nodes=${result.renderNodes.length} '
        'native=${result.nativeAvailable} '
        'worker_total_ms=${result.totalTime.inMilliseconds} '
        'wall_ms=${sw.elapsedMilliseconds}',
      );
    } finally {
      worker.dispose();
    }
  });

  testWidgets('stress render builds with external scroll + sliver mode', (
    WidgetTester tester,
  ) async {
    final List<MarkdownRenderNode> nodes = List<MarkdownRenderNode>.generate(
      1200,
      (int i) => MarkdownRenderNode(
        type: i % 40 == 0 ? 'atx_heading' : 'paragraph',
        depth: 0,
        startByte: i * 80,
        endByte: i * 80 + 79,
        startRow: i,
        endRow: i,
        raw: i % 40 == 0
            ? '# Heading $i'
            : 'Paragraph $i with **bold** text, [link](https://example.com/$i), and `code`.',
        content: i % 40 == 0
            ? '# Heading $i'
            : 'Paragraph $i with **bold** text, [link](https://example.com/$i), and `code`.',
      ),
      growable: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              StreamingMarkdownRenderView(
                nodes: nodes,
                sliver: true,
                padding: const EdgeInsets.all(8),
                tokenArrivalDelay: Duration.zero,
                tokenFadeInDuration: Duration.zero,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(StreamingMarkdownRenderView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

String _buildStressMarkdown({
  required int sections,
  required int listItemsPerSection,
  required int paragraphRepeats,
}) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < sections; i++) {
    out.writeln('# Section $i');
    out.writeln();

    for (int p = 0; p < paragraphRepeats; p++) {
      out.writeln(
        'This is stress paragraph $p in section $i with **bold**, *italic*, '
        '[link](https://example.com/$i/$p), and `inline_code` repeated for parser load.',
      );
      out.writeln();
    }

    out.writeln('| Col A | Col B | Col C |');
    out.writeln('| --- | --- | --- |');
    out.writeln('| $i | ${i + 1} | ${i + 2} |');
    out.writeln('| ${i + 3} | ${i + 4} | ${i + 5} |');
    out.writeln();

    for (int l = 0; l < listItemsPerSection; l++) {
      out.writeln('- item $l in section $i with ~~strike~~ and `tick_$l`');
    }
    out.writeln();

    out.writeln('```dart');
    out.writeln('final section = $i;');
    out.writeln('final sum = section + ${i + 1};');
    out.writeln("print('section: \$section sum: \$sum');");
    out.writeln('```');
    out.writeln();
  }
  return out.toString();
}
