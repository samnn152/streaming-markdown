import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_example/main.dart';

void main() {
  testWidgets('renders markdown example shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MarkdownExampleApp());
    expect(find.textContaining('Streaming Markdown Example'), findsOneWidget);
  });
}
