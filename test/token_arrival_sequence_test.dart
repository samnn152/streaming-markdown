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
                onTokenArrivalWait: () {
                  waitCount += 1;
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

    nodes.value = <MarkdownRenderNode>[
      _node('A', 0),
      _node('B', 10),
      _node('C', 20),
    ];
    await tester.pump();
    expect(find.text('C'), findsOneWidget);
    expect(waitCount, 2);
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
