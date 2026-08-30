import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('streaming inline-link semantics', () {
    test('Dart backend preserves the incomplete trailing link', () {
      const String source = '[help](https://';
      final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
        source,
        backend: MarkdownSyncParserBackend.dart,
      );

      expect(result.blocks, hasLength(1));
      expect(result.blocks.single.raw, source);
      expect(result.blocks.single.inlineLinks, hasLength(1));

      final MarkdownInlineLink link = result.blocks.single.inlineLinks.single;
      expect(link.label, 'help');
      expect(link.destination, 'https://');
      expect(link.isCompleted, isFalse);
      expect(link.source, source);
    });

    test('completed source transitions to a normal completed link', () {
      const String source = '[help](https://example.com)';
      final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
        source,
        backend: MarkdownSyncParserBackend.dart,
      );

      final MarkdownInlineLink link = result.blocks.single.inlineLinks.single;
      expect(link.label, 'help');
      expect(link.destination, 'https://example.com');
      expect(link.isCompleted, isTrue);
      expect(link.source, source);
    });

    test('native backend exposes the same semantic state when available', () {
      if (!isStreamingMarkdownNativeLibraryAvailable) {
        return;
      }
      const String source = '[help](https://';
      final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
        source,
        backend: MarkdownSyncParserBackend.native,
      );

      expect(result.nativeAvailable, isTrue);
      expect(result.blocks.single.raw, source);
      final MarkdownInlineLink link = result.blocks.single.inlineLinks.single;
      expect(link.label, 'help');
      expect(link.destination, 'https://');
      expect(link.isCompleted, isFalse);
    });

    test('code, autolink, and escaped syntax are not provisional links', () {
      const List<String> sources = <String>[
        '`[help](https://`',
        '<https://example.com>',
        r'\[help](https://',
      ];

      for (final String source in sources) {
        final MarkdownParseResult result = MarkdownSyncParser.parseMarkdown(
          source,
          backend: MarkdownSyncParserBackend.dart,
        );
        expect(result.blocks.single.inlineLinks, isEmpty, reason: source);
      }
    });

    test('supports escaped and nested label content at the active tail', () {
      const String source = r'[help \[nested\]](https://example.com/path';
      final MarkdownInlineLink link = parseMarkdownInlineLinks(source).single;

      expect(link.label, r'help \[nested\]');
      expect(link.destination, 'https://example.com/path');
      expect(link.isCompleted, isFalse);
      expect(link.start, 0);
      expect(link.end, source.length);
    });
  });

  group('default incomplete-link projection', () {
    testWidgets('streams empty, destination, then completed label', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<String> source = ValueNotifier<String>('[Hel');
      addTearDown(source.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: source,
            builder: (BuildContext context, String markdown, Widget? child) {
              return AnimatedStreamingMarkdown.fromMarkdown(
                markdown: markdown,
              );
            },
          ),
        ),
      );

      expect(_paintedText(tester), isNot(contains('Hel')));

      source.value = '[Hello](https://hello';
      await tester.pump();
      expect(_paintedText(tester), contains('https://hello'));
      expect(_paintedText(tester), isNot(contains('[Hello]')));

      source.value = '[Hello](https://hello)';
      await tester.pump();
      expect(_paintedText(tester), contains('Hello'));
      expect(_paintedText(tester), isNot(contains('https://hello')));
    });

    testWidgets('downstream can choose label or hidden without reparsing', (
      WidgetTester tester,
    ) async {
      const String source = '[help](https://';
      final MarkdownParseResult parsed = MarkdownSyncParser.parseMarkdown(
        source,
        backend: MarkdownSyncParserBackend.dart,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              AnimatedStreamingMarkdown(
                blocks: parsed.blocks,
                incompleteLinkTextBuilder: (MarkdownInlineLink link) {
                  return link.label;
                },
              ),
              AnimatedStreamingMarkdown(
                blocks: parsed.blocks,
                incompleteLinkTextBuilder: (MarkdownInlineLink link) => '',
              ),
            ],
          ),
        ),
      );

      expect(_paintedText(tester), contains('help'));
      expect(_paintedText(tester), isNot(contains('https://')));
    });

    testWidgets('arriving destination is clickable before completion', (
      WidgetTester tester,
    ) async {
      String? tappedDestination;
      const String source = '[Hello](https://hello';
      final MarkdownParseResult parsed = MarkdownSyncParser.parseMarkdown(
        source,
        backend: MarkdownSyncParserBackend.dart,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedStreamingMarkdown(
            blocks: parsed.blocks,
            onLinkTap: (String destination) {
              tappedDestination = destination;
            },
          ),
        ),
      );

      expect(_paintedText(tester), contains('https://hello'));
      await tester.tap(find.textContaining('https://hello'));
      await tester.pump();
      expect(tappedDestination, 'https://hello');
    });
  });
}

String _paintedText(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((RichText widget) => widget.text.toPlainText())
      .join('\n');
}
