import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_example/src/demos/link_custom_demo.dart';

void main() {
  testWidgets('link demo moves through streaming states and receives taps', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: LinkCustomDemoPage()),
    );

    expect(find.text('No inline-link semantic state'), findsNothing);
    expect(find.text('label: Hel'), findsOneWidget);
    expect(find.text('destination: '), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('link_demo_destination_prefix')),
    );
    await tester.pump();
    expect(find.text('destination: https://hello'), findsOneWidget);
    expect(find.text('completed: false'), findsOneWidget);

    final Finder renderedDestination = find.byWidgetPredicate(
      (Widget widget) =>
          widget is RichText && widget.text.toPlainText() == 'https://hello',
    );
    expect(renderedDestination, findsOneWidget);
    await tester.tap(renderedDestination);
    await tester.pump();
    expect(find.text('Clicked: https://hello'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('link_demo_completed')),
    );
    await tester.pump();
    expect(find.text('completed: true'), findsOneWidget);
  });

  testWidgets('custom object remains interactive and source selectable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: LinkCustomDemoPage()),
    );

    final Finder customObject =
        find.byKey(const ValueKey<String>('selectable_custom_widget'));
    await tester.ensureVisible(customObject);
    expect(customObject, findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    final Finder select =
        find.byKey(const ValueKey<String>('custom_widget_select_all'));
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pump();
    expect(find.text('Source: Interactive custom widget'), findsOneWidget);
  });
}
