import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('token arrival reveals sequentially and calls wait callback', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<MarkdownRenderNode>> nodes =
        ValueNotifier<List<MarkdownRenderNode>>(<MarkdownRenderNode>[
      _node('A', 0),
      _node('B', 10),
    ]);
    int waitCount = 0;
    int settledCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<MarkdownRenderNode>>(
            valueListenable: nodes,
            builder: (BuildContext context, List<MarkdownRenderNode> value, _) {
              return StreamingMarkdownRenderView(
                nodes: value,
                padding: EdgeInsets.zero,
                tokenArrivalDelay: const Duration(milliseconds: 20),
                tokenFadeInDuration: Duration.zero,
                onTokenArrivalWait: () {
                  waitCount += 1;
                },
                onSequenceSettled: () {
                  settledCount += 1;
                },
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('B'), findsOneWidget);
    expect(waitCount, 1);
    expect(settledCount, 1);

    await tester.pump();
    expect(settledCount, 1);

    nodes.value = <MarkdownRenderNode>[
      _node('A', 0),
      _node('B', 10),
      _node('C', 20),
    ];
    await tester.pump();
    expect(find.text('C'), findsOneWidget);
    expect(waitCount, 2);
    expect(settledCount, 2);
  });

  testWidgets('token animation pause stops scheduled block reveal', (
    WidgetTester tester,
  ) async {
    bool paused = false;
    final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _node('A', 0),
      _node('B', 10),
    ];

    Future<void> pumpView() {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownRenderView(
              nodes: nodes,
              padding: EdgeInsets.zero,
              tokenArrivalDelay: const Duration(milliseconds: 50),
              tokenAnimationPaused: paused,
            ),
          ),
        ),
      );
    }

    await pumpView();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);

    paused = true;
    await pumpView();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('B'), findsNothing);

    paused = false;
    await pumpView();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('next block can reveal while previous token fade is still active',
      (
    WidgetTester tester,
  ) async {
    final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[
      _node('Alpha', 0),
      _node('Beta', 10),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: nodes,
            padding: EdgeInsets.zero,
            tokenArrivalDelay: const Duration(milliseconds: 20),
            tokenFadeInDuration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('inline tokens reveal by interval while prior fade is active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownRenderView(
            nodes: <MarkdownRenderNode>[_node('Alpha Beta Gamma', 0)],
            padding: EdgeInsets.zero,
            tokenArrivalDelay: const Duration(milliseconds: 20),
            tokenFadeInDuration: const Duration(milliseconds: 200),
            tokenFadeInCurve: Curves.linear,
            tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
          ),
        ),
      ),
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsNothing);

    final Finder alphaOpacity = find.ancestor(
      of: find.text('Alpha'),
      matching: find.byType(Opacity),
    );
    expect(alphaOpacity, findsOneWidget);
    expect(tester.widget<Opacity>(alphaOpacity).opacity, lessThan(1));

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Gamma'), findsOneWidget);
    expect(tester.widget<Opacity>(alphaOpacity).opacity, lessThan(1));
  });

  testWidgets('next block waits when previous streamed block grows', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<MarkdownRenderNode>> nodes =
        ValueNotifier<List<MarkdownRenderNode>>(<MarkdownRenderNode>[
      _node('Alpha', 0),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<MarkdownRenderNode>>(
            valueListenable: nodes,
            builder: (BuildContext context, List<MarkdownRenderNode> value, _) {
              return StreamingMarkdownRenderView(
                nodes: value,
                padding: EdgeInsets.zero,
                tokenArrivalDelay: const Duration(milliseconds: 20),
                tokenFadeInDuration: const Duration(milliseconds: 100),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Alpha'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    nodes.value = <MarkdownRenderNode>[
      _node('Alpha beta gamma delta', 0),
      _node('Next', 100),
    ];
    await tester.pump();

    expect(find.text('Next'), findsNothing);

    await tester.pump(const Duration(milliseconds: 70));
    expect(find.text('Next'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('streaming updates do not indefinitely postpone pending block', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<MarkdownRenderNode>> nodes =
        ValueNotifier<List<MarkdownRenderNode>>(<MarkdownRenderNode>[
      _node('Hello', 0),
      _node('Next', 100),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<MarkdownRenderNode>>(
            valueListenable: nodes,
            builder: (BuildContext context, List<MarkdownRenderNode> value, _) {
              return StreamingMarkdownRenderView(
                nodes: value,
                padding: EdgeInsets.zero,
                tokenArrivalDelay: const Duration(milliseconds: 20),
                tokenFadeInDuration: const Duration(milliseconds: 120),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      nodes.value = <MarkdownRenderNode>[
        _node('Hello ${List<String>.filled(i + 1, 'token').join(' ')}', 0),
        _node('Next', 100),
      ];
      await tester.pump();
    }

    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Next'), findsOneWidget);
  });
}

MarkdownRenderNode _node(String raw, int startByte) {
  return MarkdownRenderNode(
    type: 'paragraph',
    depth: 0,
    startByte: startByte,
    endByte: startByte + raw.length,
    startRow: 0,
    endRow: 0,
    raw: raw,
    content: raw,
  );
}
