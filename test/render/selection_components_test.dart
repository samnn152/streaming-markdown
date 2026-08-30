import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('complete Markdown selection coverage', () {
    test('projection matches every rendered core component', () {
      final Map<List<MarkdownRenderNode>, String> cases =
          <List<MarkdownRenderNode>, String>{
        <MarkdownRenderNode>[
          _node(
            'atx_heading',
            '# Heading **bold**',
            content: 'Heading **bold**',
          ),
        ]: 'Heading bold',
        <MarkdownRenderNode>[
          _node(
            'setext_heading',
            'Setext _italic_\n===============',
            content: 'Setext _italic_',
          ),
        ]: 'Setext italic',
        <MarkdownRenderNode>[
          _node(
            'paragraph',
            'Plain **bold** _italic_ ~~strike~~ `code` '
                '[link](https://e.dev)',
          ),
        ]: 'Plain bold italic strike code link',
        <MarkdownRenderNode>[
          _node('block_quote', '> Quoted **bold**'),
        ]: 'Quoted bold',
        <MarkdownRenderNode>[
          _node(
            'block_quote',
            '> [!NOTE] Custom title\n> Body **bold**',
          ),
        ]: 'Custom title\nBody bold',
        <MarkdownRenderNode>[
          _node('front_matter', '---\ntitle: **Demo**\n---'),
        ]: '---\ntitle: Demo\n---',
        <MarkdownRenderNode>[
          _node('footnote_definition', '[^a]: Footnote **bold**'),
        ]: 'a: Footnote bold',
        <MarkdownRenderNode>[
          _node('paragraph', '[^a]: Footnote **bold**'),
        ]: 'a: Footnote bold',
        <MarkdownRenderNode>[
          _node(
            'html_block',
            '<section><h2>First</h2>'
                '<p>Second <strong>bold</strong></p>'
                '<ul><li>One</li><li>Two</li></ul>'
                '<table><tr><th>A</th><th>B</th></tr>'
                '<tr><td>1</td><td>2</td></tr></table></section>',
          ),
        ]: 'First\nSecond bold\nOne\nTwo\nA\nB\n1\n2',
        <MarkdownRenderNode>[
          _node('pipe_table', '| A | B |\n| --- | --- |\n| 1 | **2** |'),
        ]: 'AB12',
        <MarkdownRenderNode>[
          _node('list', '- one\n1. two\n- [x] done'),
        ]: 'one\ntwo\ndone',
        <MarkdownRenderNode>[
          _node('fenced_code_block', '```dart\nprint(1);\n```'),
        ]: 'print(1);',
        <MarkdownRenderNode>[
          _node('paragraph', '![cat](https://example.invalid/cat.png)'),
        ]: '[image: cat]',
        <MarkdownRenderNode>[
          _node('paragraph', r'$$x+1$$'),
        ]: r'$$x+1$$',
        <MarkdownRenderNode>[
          _node(
            'paragraph',
            r'Before ![cat](https://example.invalid/cat.png) and $x+1$ after',
          ),
        ]: r'Before [image: cat] and $x+1$ after',
      };

      for (final MapEntry<List<MarkdownRenderNode>, String> entry
          in cases.entries) {
        expect(
          StreamingMarkdownRenderView.debugFullPlainText(nodes: entry.key),
          entry.value,
        );
      }
    });

    testWidgets('select-all paints every component proxy completely', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final List<_GeometryCase> cases = <_GeometryCase>[
        _GeometryCase(
          <MarkdownRenderNode>[
            _node(
              'atx_heading',
              '# Heading **bold**',
              content: 'Heading **bold**',
            ),
          ],
          const <String>['Heading bold'],
          const <int>[0],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('block_quote', '> Quoted **bold**'),
          ],
          const <String>['Quoted bold'],
          const <int>[0],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node(
              'block_quote',
              '> [!NOTE] Custom title\n> Body **bold**',
            ),
          ],
          const <String>['Custom title', 'Body bold'],
          const <int>[0, 13],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('footnote_definition', '[^a]: Footnote **bold**'),
          ],
          const <String>['a: Footnote bold'],
          const <int>[0],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('front_matter', '---\ntitle: **Demo**\n---'),
          ],
          const <String>['---\ntitle: Demo\n---'],
          const <int>[0],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node(
              'html_block',
              '<section><h2>First</h2>'
                  '<p>Second <strong>bold</strong></p>'
                  '<ul><li>One</li><li>Two</li></ul>'
                  '<table><tr><th>A</th><th>B</th></tr>'
                  '<tr><td>1</td><td>2</td></tr></table></section>',
            ),
          ],
          const <String>[
            'First',
            'Second bold',
            'One',
            'Two',
            'A',
            'B',
            '1',
            '2'
          ],
          const <int>[0, 6, 18, 22, 26, 28, 30, 32],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('html_block', '<img alt="cat">'),
          ],
          const <String>['[image: cat]'],
          const <int>[0],
          atomicProxyIndexes: <int>{0},
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node(
              'html_block',
              '<p>Before <img alt="cat"> after</p>',
            ),
          ],
          const <String>['Before [image: cat] after'],
          const <int>[0],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('pipe_table', '| A | B |\n| --- | --- |\n| 1 | **2** |'),
          ],
          const <String>['A', 'B', '1', '2'],
          const <int>[0, 1, 2, 3],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('list', '- one\n1. two\n- [x] done'),
          ],
          const <String>['one', 'two', 'done'],
          const <int>[0, 4, 8],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('fenced_code_block', '```dart\nprint(1);\n```'),
          ],
          const <String>['print(1);'],
          const <int>[0],
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node('paragraph', '![cat](https://example.invalid/cat.png)'),
          ],
          const <String>['[image: cat]'],
          const <int>[0],
          atomicProxyIndexes: <int>{0},
        ),
        _GeometryCase(
          <MarkdownRenderNode>[_node('paragraph', r'$$x+1$$')],
          const <String>[r'$$x+1$$'],
          const <int>[0],
          atomicProxyIndexes: <int>{0},
        ),
        _GeometryCase(
          <MarkdownRenderNode>[
            _node(
              'paragraph',
              r'Before ![cat](https://example.invalid/cat.png) and $x+1$ after',
            ),
          ],
          const <String>[r'Before [image: cat] and $x+1$ after'],
          const <int>[0],
        ),
      ];

      for (final _GeometryCase component in cases) {
        final AnimatedMarkdownSelectionController controller =
            AnimatedMarkdownSelectionController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StreamingMarkdownRenderView(
                nodes: component.nodes,
                padding: EdgeInsets.zero,
                enableTextSelection: true,
                selectionController: controller,
                tokenArrivalDelay: Duration.zero,
                tokenFadeInDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                customImageBuilder: _testImageBuilder,
                customLatexBuilder: _testLatexBuilder,
              ),
            ),
          ),
        );
        await tester.pump();
        controller.selectAll();
        await tester.pump();

        final List<Element> proxyElements = find
            .byWidgetPredicate(
              (Widget widget) =>
                  widget.runtimeType.toString() == '_SelectableInlineTextProxy',
            )
            .evaluate()
            .toList(growable: false);
        final List<String> proxyTexts = <String>[];
        final List<int> proxyStarts = <int>[];
        for (int index = 0; index < proxyElements.length; index++) {
          final dynamic widget = proxyElements[index].widget;
          final dynamic renderObject = proxyElements[index].renderObject;
          final String plainText = widget.plainText as String;
          proxyTexts.add(plainText);
          proxyStarts.add(renderObject.absolutePlainTextStart as int);
          expect(
            renderObject.debugPaintSelectionRange,
            TextRange(start: 0, end: plainText.length),
            reason: 'Selection did not cover "$plainText" completely.',
          );
          expect(
            widget.atomic as bool,
            component.atomicProxyIndexes.contains(index),
          );
        }
        expect(proxyTexts, component.proxyTexts);
        expect(proxyStarts, component.proxyStarts);

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    });

    testWidgets('selection is one flat layer, never per-token backgrounds', (
      WidgetTester tester,
    ) async {
      const Color selectionColor = Color(0xFFFF00FF);
      const String markdown = 'Flat **selection** across several words.';
      final GlobalKey boundaryKey = GlobalKey();
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: 700,
                  height: 100,
                  child: StreamingMarkdownRenderView(
                    nodes: <MarkdownRenderNode>[_node('paragraph', markdown)],
                    padding: EdgeInsets.zero,
                    enableTextSelection: true,
                    selectionController: controller,
                    tokenArrivalDelay: Duration.zero,
                    tokenFadeInDuration: Duration.zero,
                    tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                    markdownTheme: const StreamingMarkdownThemeData(
                      selectionColor: selectionColor,
                      paragraphTextStyle: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.selectAll();
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget.runtimeType.toString() == '_InlineSourceSelectionBackdrop',
        ),
        findsNothing,
      );
      for (final RichText richText
          in tester.widgetList<RichText>(find.byType(RichText))) {
        expect(
          _hasBackgroundColor(richText.text, selectionColor),
          isFalse,
          reason: 'Selection color leaked into an individual token span.',
        );
      }

      final _RawImageData image = await _captureBoundary(tester, boundaryKey);
      final _OpaqueRow row = _longestOpaqueColorRow(image, selectionColor);
      expect(row.width, greaterThan(250));
      final Element proxy = find
          .byWidgetPredicate(
            (Widget widget) =>
                widget.runtimeType.toString() == '_SelectableInlineTextProxy',
          )
          .evaluate()
          .single;
      final List<Rect> paintRects = ((proxy.renderObject! as dynamic)
              .debugPaintSelectionRects as List<dynamic>)
          .cast<Rect>();
      expect(
        paintRects.length,
        lessThanOrEqualTo(2),
        reason: 'Each visual line must be one surface, not per-token layers.',
      );
      expect(
        paintRects.map((Rect rect) => rect.width).reduce(
              (double total, double width) => total + width,
            ),
        greaterThan(650),
      );
    });

    testWidgets('animated token selection follows the real wrapped line', (
      WidgetTester tester,
    ) async {
      const String markdown = '''Kết luận: Bạn chọn ai?

- Nếu bạn thích một **nghệ sĩ** điều khiển quả bóng như có phép thuật, người có thể tự mình tạo ra cơ hội từ hư vô bằng những bước chạy thanh thoát → **Chọn Messi.**
- Nếu bạn thích một **chiến binh** quả cảm, một cỗ máy săn bàn hoàn hảo, người luôn vượt qua mọi giới hạn của bản thân để chiến thắng → **Chọn Ronaldo.**''';
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: StreamingMarkdownRenderView(
                nodes: <MarkdownRenderNode>[
                  _node('paragraph', 'Kết luận: Bạn chọn ai?'),
                  _node(
                    'list',
                    markdown.substring(markdown.indexOf('- Nếu')),
                  ),
                ],
                padding: EdgeInsets.zero,
                enableTextSelection: true,
                selectionController: controller,
                tokenArrivalDelay: Duration.zero,
                tokenFadeInDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                markdownTheme: const StreamingMarkdownThemeData(
                  paragraphTextStyle: TextStyle(fontSize: 20, height: 1.2),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.selectAll();
      await tester.pump();

      final Element messiToken = find
          .byWidgetPredicate(
            (Widget widget) =>
                widget.runtimeType.toString() ==
                    '_MarkdownSelectableTextSpan' &&
                (widget as dynamic).text == 'Messi.',
          )
          .evaluate()
          .single;
      final Element proxy = find
          .ancestor(
            of: find.byElementPredicate(
              (Element element) => identical(element, messiToken),
            ),
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget.runtimeType.toString() == '_SelectableInlineTextProxy',
            ),
          )
          .evaluate()
          .single;
      final RenderBox proxyBox = proxy.renderObject! as RenderBox;
      final List<Element> tokenElements = find
          .descendant(
            of: find.byElementPredicate(
              (Element element) => identical(element, proxy),
            ),
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget.runtimeType.toString() ==
                  '_MarkdownSelectableTextSpan',
            ),
          )
          .evaluate()
          .toList(growable: false);
      final List<Rect> tokenRects = tokenElements.map((Element element) {
        final RenderBox tokenBox = element.renderObject! as RenderBox;
        return MatrixUtils.transformRect(
          tokenBox.getTransformTo(proxyBox),
          Offset.zero & tokenBox.size,
        );
      }).toList(growable: false);
      final RenderBox messiBox = messiToken.renderObject! as RenderBox;
      final Rect messiRect = MatrixUtils.transformRect(
        messiBox.getTransformTo(proxyBox),
        Offset.zero & messiBox.size,
      );
      final List<Rect> paintRects = ((proxy.renderObject! as dynamic)
              .debugPaintSelectionRects as List<dynamic>)
          .cast<Rect>();
      final Rect messiSelectionLine = paintRects.singleWhere(
        (Rect rect) =>
            rect.top <= messiRect.center.dy &&
            rect.bottom >= messiRect.center.dy,
      );
      final double actualLineEnd = tokenRects
          .where(
            (Rect rect) =>
                rect.top <= messiRect.center.dy &&
                rect.bottom >= messiRect.center.dy,
          )
          .map((Rect rect) => rect.right)
          .reduce((double a, double b) => a > b ? a : b);

      expect(messiSelectionLine.right, closeTo(actualLineEnd, 0.5));
      expect(
        proxyBox.size.width - messiSelectionLine.right,
        greaterThan(20),
        reason: 'The Messi line must not select unused trailing width.',
      );
    });

    testWidgets('inline code joins the flat alpha selection surface', (
      WidgetTester tester,
    ) async {
      const Color selectionColor = Color(0x663B82F6);
      const Color inlineCodeColor = Color(0xFFFF0000);
      final GlobalKey boundaryKey = GlobalKey();
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: 700,
                  height: 100,
                  child: StreamingMarkdownRenderView(
                    nodes: <MarkdownRenderNode>[
                      _node('paragraph', 'Before `inline code` after.'),
                    ],
                    padding: EdgeInsets.zero,
                    enableTextSelection: true,
                    selectionController: controller,
                    tokenArrivalDelay: Duration.zero,
                    tokenFadeInDuration: Duration.zero,
                    tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                    markdownTheme: const StreamingMarkdownThemeData(
                      selectionColor: selectionColor,
                      inlineCodeBackgroundColor: inlineCodeColor,
                      paragraphTextStyle: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.selectAll();
      await tester.pump();

      final Finder inlineCodeMarker = find.byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_MarkdownSelectableTextSpan' &&
            (widget as dynamic).text == 'inline code',
      );
      expect(
        inlineCodeMarker,
        findsOneWidget,
        reason: 'Inline code must expose its full visual bounds to selection.',
      );
      final Element markerElement = inlineCodeMarker.evaluate().single;
      final Element proxyElement = find
          .ancestor(
            of: inlineCodeMarker,
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget.runtimeType.toString() == '_SelectableInlineTextProxy',
            ),
          )
          .evaluate()
          .single;
      final RenderBox markerBox = markerElement.renderObject! as RenderBox;
      final RenderBox proxyBox = proxyElement.renderObject! as RenderBox;
      final Rect markerRectInProxy = MatrixUtils.transformRect(
        markerBox.getTransformTo(proxyBox),
        Offset.zero & markerBox.size,
      );
      final List<Rect> paintRects = ((proxyElement.renderObject! as dynamic)
              .debugPaintSelectionRects as List<dynamic>)
          .cast<Rect>();
      final Rect selectedLine = paintRects.singleWhere(
        (Rect rect) => rect.overlaps(markerRectInProxy),
      );
      expect(selectedLine.left, lessThanOrEqualTo(markerRectInProxy.left));
      expect(selectedLine.top, lessThanOrEqualTo(markerRectInProxy.top));
      expect(selectedLine.right, greaterThanOrEqualTo(markerRectInProxy.right));
      expect(
        selectedLine.bottom,
        greaterThanOrEqualTo(markerRectInProxy.bottom),
      );

      final _RawImageData image = await _captureBoundary(tester, boundaryKey);
      final Rect boundaryRect = tester.getRect(find.byKey(boundaryKey));
      final Finder inlineCodeBox = find.byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() ==
                '_MarkdownSelectionAwareBackground' &&
            (widget as dynamic).color == inlineCodeColor,
      );
      expect(inlineCodeBox, findsOneWidget);
      final Rect decorationRect = tester.getRect(inlineCodeBox);
      final Offset paddingSample = Offset(
            decorationRect.left + 4,
            decorationRect.center.dy,
          ) -
          boundaryRect.topLeft;
      final Color paintedPadding =
          image.colorAt(paddingSample.dx.floor(), paddingSample.dy.floor());
      expect(
        _colorsNear(
          paintedPadding,
          Color.alphaBlend(selectionColor, Colors.white),
        ),
        isTrue,
        reason:
            'A fully selected inline-code box must join the same flat surface '
            'instead of blending into a separate rounded pill.',
      );
    });

    testWidgets('pointer drag uses the decorated inline-code geometry', (
      WidgetTester tester,
    ) async {
      const String source = 'Before `inline code` after.';
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              child: StreamingMarkdownRenderView(
                nodes: <MarkdownRenderNode>[
                  _node('paragraph', source),
                ],
                padding: EdgeInsets.zero,
                enableTextSelection: true,
                selectionController: controller,
                tokenArrivalDelay: Duration.zero,
                tokenFadeInDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                markdownTheme: const StreamingMarkdownThemeData(
                  paragraphTextStyle: TextStyle(fontSize: 20, height: 1.4),
                  inlineCodeTextStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder marker = find.byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_MarkdownSelectableTextSpan' &&
            (widget as dynamic).text == 'inline code',
      );
      expect(marker, findsOneWidget);
      final Rect markerRect = tester.getRect(marker);
      final TestGesture gesture = await tester.startGesture(
        Offset(markerRect.left + 1, markerRect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(Offset(markerRect.right - 1, markerRect.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(controller.value.hasSelection, isTrue);
      expect(controller.value.selectedMarkdown, '`inline code`');

      final Element proxyElement = find
          .ancestor(
            of: marker,
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget.runtimeType.toString() == '_SelectableInlineTextProxy',
            ),
          )
          .evaluate()
          .single;
      final RenderBox markerBox =
          marker.evaluate().single.renderObject! as RenderBox;
      final RenderBox proxyBox = proxyElement.renderObject! as RenderBox;
      final Rect markerRectInProxy = MatrixUtils.transformRect(
        markerBox.getTransformTo(proxyBox),
        Offset.zero & markerBox.size,
      );
      final List<Rect> paintRects = ((proxyElement.renderObject! as dynamic)
              .debugPaintSelectionRects as List<dynamic>)
          .cast<Rect>();
      expect(
        paintRects.any(
          (Rect rect) =>
              rect.left <= markerRectInProxy.left &&
              rect.top <= markerRectInProxy.top &&
              rect.right >= markerRectInProxy.right &&
              rect.bottom >= markerRectInProxy.bottom,
        ),
        isTrue,
        reason: 'A full pointer selection must cover the decorated code box.',
      );

      final TestGesture dismissGesture = await tester.startGesture(
        markerRect.center,
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(dismissGesture.removePointer);
      await dismissGesture.up();
      await tester.pump();
      await tester.pump();
      expect(
        controller.value.hasSelection,
        isFalse,
        reason: 'One click inside selected inline code must dismiss selection.',
      );
    });

    testWidgets('demo-line drag includes inline code and trailing punctuation',
        (
      WidgetTester tester,
    ) async {
      const String source = 'Select across **bold text**, *italics*, '
          '[a link](https://pub.dev), and `inline code`.';
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: AnimatedStreamingMarkdown.fromMarkdown(
                markdown: source,
                padding: EdgeInsets.zero,
                enableSelection: true,
                selectionController: controller,
                tokenStaggerDelay: Duration.zero,
                tokenAnimationDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Finder marker(String text) => find.byWidgetPredicate(
            (Widget widget) =>
                widget.runtimeType.toString() ==
                    '_MarkdownSelectableTextSpan' &&
                (widget as dynamic).text == text,
          );
      final Finder across = marker('across');
      final Finder code = marker('inline code');
      final Finder period = marker('.');
      expect(across, findsOneWidget);
      expect(code, findsOneWidget);
      expect(period, findsOneWidget);
      final Rect acrossRect = tester.getRect(across);
      final Rect periodRect = tester.getRect(period);

      final TestGesture gesture = await tester.startGesture(
        Offset(acrossRect.left + 1, acrossRect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        Offset(periodRect.right - 0.25, periodRect.center.dy),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(controller.value.selectedMarkdown, startsWith('across'));
      expect(controller.value.selectedMarkdown, endsWith('`inline code`.'));

      final Element proxyElement = find
          .ancestor(
            of: code,
            matching: find.byWidgetPredicate(
              (Widget widget) =>
                  widget.runtimeType.toString() == '_SelectableInlineTextProxy',
            ),
          )
          .evaluate()
          .single;
      final RenderBox proxyBox = proxyElement.renderObject! as RenderBox;
      final RenderBox acrossBox =
          across.evaluate().single.renderObject! as RenderBox;
      final RenderBox codeBox =
          code.evaluate().single.renderObject! as RenderBox;
      final RenderBox periodBox =
          period.evaluate().single.renderObject! as RenderBox;
      final Rect acrossInProxy = MatrixUtils.transformRect(
        acrossBox.getTransformTo(proxyBox),
        Offset.zero & acrossBox.size,
      );
      final Rect codeInProxy = MatrixUtils.transformRect(
        codeBox.getTransformTo(proxyBox),
        Offset.zero & codeBox.size,
      );
      final Rect periodInProxy = MatrixUtils.transformRect(
        periodBox.getTransformTo(proxyBox),
        Offset.zero & periodBox.size,
      );
      final List<Rect> paintRects = ((proxyElement.renderObject! as dynamic)
              .debugPaintSelectionRects as List<dynamic>)
          .cast<Rect>();
      expect(
        paintRects.any(
          (Rect rect) =>
              rect.left <= acrossInProxy.left + 2 &&
              rect.right >= codeInProxy.right &&
              rect.right >= periodInProxy.right,
        ),
        isTrue,
      );
    });

    testWidgets('decorated inline gaps expose both whitespace carets', (
      WidgetTester tester,
    ) async {
      const String source = 'Start `wide code` after.';
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: AnimatedStreamingMarkdown.fromMarkdown(
                markdown: source,
                padding: EdgeInsets.zero,
                enableSelection: true,
                selectionController: controller,
                tokenStaggerDelay: Duration.zero,
                tokenAnimationDuration: Duration.zero,
                tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                theme: const AnimatedMarkdownThemeData(
                  paragraphTextStyle: TextStyle(fontSize: 20),
                  inlineCodeTextStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Finder marker(String text) => find.byWidgetPredicate(
            (Widget widget) =>
                widget.runtimeType.toString() ==
                    '_MarkdownSelectableTextSpan' &&
                (widget as dynamic).text == text,
          );
      final Rect start = tester.getRect(marker('Start'));
      final Rect code = tester.getRect(marker('wide code'));
      final Rect after = tester.getRect(marker('after.'));
      expect(after.left, greaterThan(code.right));

      final TestGesture gesture = await tester.startGesture(
        Offset(start.left + 0.5, start.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        Offset(code.right + (after.left - code.right) * 0.25, code.center.dy),
      );
      await tester.pump();
      expect(controller.value.selectedMarkdown, 'Start `wide code`');

      await gesture.moveTo(
        Offset(code.right + (after.left - code.right) * 0.75, code.center.dy),
      );
      await tester.pump();
      expect(controller.value.selectedMarkdown, 'Start `wide code` ');

      await gesture.up();
      await tester.pump();
    });

    testWidgets('flat selection covers real inline image and LaTeX bounds', (
      WidgetTester tester,
    ) async {
      const Color selectionColor = Color(0xFFFF00FF);
      final GlobalKey boundaryKey = GlobalKey();
      final GlobalKey imageKey = GlobalKey();
      final GlobalKey latexKey = GlobalKey();
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: Colors.white,
                child: StreamingMarkdownRenderView(
                  nodes: <MarkdownRenderNode>[
                    _node(
                      'paragraph',
                      r'Before ![cat](https://example.invalid/cat.png) and $x+1$ after',
                    ),
                  ],
                  padding: EdgeInsets.zero,
                  enableTextSelection: true,
                  selectionController: controller,
                  tokenArrivalDelay: Duration.zero,
                  tokenFadeInDuration: Duration.zero,
                  tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                  markdownTheme: const StreamingMarkdownThemeData(
                    selectionColor: selectionColor,
                  ),
                  customImageBuilder: (
                    BuildContext context,
                    StreamingMarkdownImageBuildContext image,
                  ) {
                    return SizedBox(
                      key: imageKey,
                      width: 120,
                      height: 36,
                      child: const ColoredBox(color: Colors.red),
                    );
                  },
                  customLatexBuilder: (
                    BuildContext context,
                    StreamingMarkdownLatexBuildContext latex,
                  ) {
                    return SizedBox(
                      key: latexKey,
                      width: 90,
                      height: 32,
                      child: const ColoredBox(color: Colors.green),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.selectAll();
      await tester.pump();

      final _RawImageData image = await _captureBoundary(tester, boundaryKey);
      final Rect boundaryRect = tester.getRect(find.byKey(boundaryKey));
      for (final GlobalKey atomicKey in <GlobalKey>[imageKey, latexKey]) {
        final Rect atomicRect = tester.getRect(find.byKey(atomicKey));
        final Offset sample = atomicRect.center - boundaryRect.topLeft;
        expect(
          image.colorAt(sample.dx.floor(), sample.dy.floor()),
          selectionColor,
          reason: 'Atomic Markdown content was not covered by selection.',
        );
      }
    });

    testWidgets('touch long-press can select an atomic image block', (
      WidgetTester tester,
    ) async {
      const String source = '![cat](https://example.invalid/cat.png)';
      const ValueKey<String> imageKey = ValueKey<String>('touch-image');
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamingMarkdownRenderView(
              nodes: <MarkdownRenderNode>[_node('paragraph', source)],
              padding: EdgeInsets.zero,
              enableTextSelection: true,
              selectionController: controller,
              tokenArrivalDelay: Duration.zero,
              tokenFadeInDuration: Duration.zero,
              customImageBuilder: (
                BuildContext context,
                StreamingMarkdownImageBuildContext image,
              ) {
                return const SizedBox(
                  key: imageKey,
                  width: 240,
                  height: 100,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.longPressAt(tester.getCenter(find.byKey(imageKey)));
      await tester.pump();

      expect(controller.value.hasSelection, isTrue);
      expect(controller.value.selectedMarkdown, source);
    });

    testWidgets('sliver remount rehydrates flat and atomic selection paint', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 170));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final AnimatedMarkdownSelectionController controller =
          AnimatedMarkdownSelectionController();
      final ScrollController scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);
      final List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[];
      int sourceCursor = 0;
      for (int index = 0; index < 24; index++) {
        final String raw = 'Lazy paragraph $index keeps its semantic offset.';
        nodes.add(_node('paragraph', raw, start: sourceCursor));
        sourceCursor += raw.length + 2;
      }
      const String imageSource = '![last](https://example.invalid/sliver.png)';
      nodes.add(_node('paragraph', imageSource, start: sourceCursor));
      sourceCursor += imageSource.length + 2;
      nodes.add(_node('paragraph', r'$$x_{last}$$', start: sourceCursor));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedStreamingMarkdownSelectionArea(
              controller: controller,
              child: CustomScrollView(
                controller: scrollController,
                slivers: <Widget>[
                  AnimatedStreamingMarkdown(
                    blocks: nodes,
                    asSliver: true,
                    padding: EdgeInsets.zero,
                    enableSelection: true,
                    selectionController: controller,
                    tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
                    imageBuilder: _testImageBuilder,
                    latexBuilder: _testLatexBuilder,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final String sourceSnapshot = controller.value.sourceText;
      controller.selectAll();
      for (int frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(scrollController.offset, greaterThan(0));
      expect(controller.value.selectedMarkdown, sourceSnapshot);
      final List<Element> mountedAtomicProxies = find
          .byWidgetPredicate(
            (Widget widget) =>
                widget.runtimeType.toString() == '_SelectableInlineTextProxy' &&
                (widget as dynamic).atomic == true,
          )
          .evaluate()
          .toList(growable: false);
      expect(mountedAtomicProxies, isNotEmpty);
      for (final Element element in mountedAtomicProxies) {
        final dynamic widget = element.widget;
        final dynamic renderObject = element.renderObject;
        final String plainText = widget.plainText as String;
        expect(
          renderObject.debugPaintSelectionRange,
          TextRange(start: 0, end: plainText.length),
        );
      }

      scrollController.jumpTo(0);
      await tester.pump();
      expect(controller.value.selectedMarkdown, sourceSnapshot);
    });
  });
}

class _GeometryCase {
  const _GeometryCase(
    this.nodes,
    this.proxyTexts,
    this.proxyStarts, {
    this.atomicProxyIndexes = const <int>{},
  });

  final List<MarkdownRenderNode> nodes;
  final List<String> proxyTexts;
  final List<int> proxyStarts;
  final Set<int> atomicProxyIndexes;
}

class _RawImageData {
  const _RawImageData(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final Uint8List bytes;

  Color colorAt(int x, int y) {
    final int offset = (y * width + x) * 4;
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  }
}

class _OpaqueRow {
  const _OpaqueRow({required this.width, required this.coloredPixels});

  final int width;
  final int coloredPixels;
}

bool _colorsNear(Color actual, Color expected, {int tolerance = 2}) {
  int argb(Color color) {
    final dynamic dynamicColor = color;
    try {
      return dynamicColor.toARGB32() as int;
    } on NoSuchMethodError {
      return dynamicColor.value as int;
    }
  }

  final int actualValue = argb(actual);
  final int expectedValue = argb(expected);
  for (final int shift in <int>[0, 8, 16, 24]) {
    final int actualChannel = (actualValue >> shift) & 0xFF;
    final int expectedChannel = (expectedValue >> shift) & 0xFF;
    if ((actualChannel - expectedChannel).abs() > tolerance) {
      return false;
    }
  }
  return true;
}

Future<_RawImageData> _captureBoundary(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  final RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync<_RawImageData>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData bytes =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final _RawImageData result = _RawImageData(
      image.width,
      image.height,
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    image.dispose();
    return result;
  }))!;
}

_OpaqueRow _longestOpaqueColorRow(_RawImageData image, Color color) {
  _OpaqueRow best = const _OpaqueRow(width: 0, coloredPixels: 0);
  for (int y = 0; y < image.height; y++) {
    int? first;
    int? last;
    int count = 0;
    for (int x = 0; x < image.width; x++) {
      if (image.colorAt(x, y) != color) {
        continue;
      }
      first ??= x;
      last = x;
      count += 1;
    }
    if (first == null || last == null) {
      continue;
    }
    final _OpaqueRow row = _OpaqueRow(
      width: last - first + 1,
      coloredPixels: count,
    );
    if (row.width > best.width) {
      best = row;
    }
  }
  return best;
}

bool _hasBackgroundColor(InlineSpan span, Color color) {
  if (span is! TextSpan) {
    return false;
  }
  if (span.style?.backgroundColor == color) {
    return true;
  }
  return (span.children ?? const <InlineSpan>[]).any(
    (InlineSpan child) => _hasBackgroundColor(child, color),
  );
}

Widget _testImageBuilder(
  BuildContext context,
  StreamingMarkdownImageBuildContext image,
) {
  return SizedBox(
    width: image.inline ? 80 : 240,
    height: image.inline ? 32 : 100,
  );
}

Widget _testLatexBuilder(
  BuildContext context,
  StreamingMarkdownLatexBuildContext latex,
) {
  return SizedBox(
    width: latex.display ? 180 : 70,
    height: latex.display ? 54 : 28,
  );
}

MarkdownRenderNode _node(
  String type,
  String raw, {
  int start = 0,
  String? content,
}) {
  return MarkdownRenderNode(
    type: type,
    depth: 0,
    startByte: start,
    endByte: start + raw.length,
    startRow: 0,
    endRow: '\n'.allMatches(raw).length,
    raw: raw,
    content: content ?? raw,
  );
}
