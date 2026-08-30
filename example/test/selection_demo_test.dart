import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_example/src/demos/selection_demo.dart';

void main() {
  testWidgets('selection lab explains and exposes the local fixture', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: SelectionDemoPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selection, made visible'), findsOneWidget);
    expect(find.text('Local Markdown fixture'), findsOneWidget);
    expect(
      find.text('Drag through spaces and past the final period below'),
      findsOneWidget,
    );
    expect(find.text('Drag text'), findsOneWidget);
    expect(find.text('Rich HTML'), findsOneWidget);
    expect(find.text('Nothing selected yet'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('selection_demo_markdown')),
        findsOneWidget);
  });

  testWidgets('selection lab selects all and switches copy strategy', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: SelectionDemoPage()),
    );
    await tester.pumpAndSettle();

    final Finder selectAll = find.byKey(
      const ValueKey<String>('selection_demo_select_all'),
    );
    await tester.ensureVisible(selectAll);
    await tester.tap(selectAll);
    await tester.pump();
    await tester.pump();

    expect(find.text('Selection is ready to copy'), findsOneWidget);
    expect(find.textContaining('characters selected'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('selection_demo_strategy')),
    );
    await tester.pump();
    await tester.tap(find.text('Raw Markdown').last);
    await tester.pump();

    expect(find.text('Raw Markdown'), findsOneWidget);
    expect(
      find.textContaining('Keeps the source syntax'),
      findsOneWidget,
    );
  });
}
