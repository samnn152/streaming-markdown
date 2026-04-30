import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:streaming_markdown_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records README Gemini streaming demo', (
    WidgetTester tester,
  ) async {
    app.main();

    await tester.pumpAndSettle(const Duration(seconds: 2));

    final Finder questionField = find.byType(TextField).first;
    await tester.tap(questionField);
    await tester.enterText(
      questionField,
      'Show a compact markdown demo with a heading, bullets, a table, and Dart code.',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.tap(find.text('Submit both'));
    await tester.pump(const Duration(seconds: 1));

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Answer received.').evaluate().isNotEmpty) {
        break;
      }
    }

    await tester.pump(const Duration(seconds: 4));
  });
}
