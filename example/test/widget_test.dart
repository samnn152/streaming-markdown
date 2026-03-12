import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders basic smoke widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('streaming-markdown-example-smoke')),
      ),
    );
    expect(find.text('streaming-markdown-example-smoke'), findsOneWidget);
  });
}
