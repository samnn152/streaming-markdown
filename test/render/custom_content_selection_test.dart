import 'dart:ui' as ui;

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        MatrixUtils,
        RenderEditable,
        RenderObject,
        RenderParagraph,
        RenderRepaintBoundary,
        Selectable;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('custom LaTeX remains selectable without an extra wrapper', (
    WidgetTester tester,
  ) async {
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: r'Before $x$ after',
          enableSelection: true,
          selectionController: controller,
          latexBuilder: (
            BuildContext context,
            StreamingMarkdownLatexBuildContext latex,
          ) {
            return const Icon(Icons.functions, key: ValueKey<String>('math'));
          },
        ),
      ),
    );

    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('math')), findsOneWidget);
    expect(controller.value.selectedMarkdown, r'Before $x$ after');
    expect(_selectedPlainText(tester), contains(r'$x$'));
  });

  testWidgets('wrapper makes a fully custom block atomically selectable', (
    WidgetTester tester,
  ) async {
    const String source = 'Custom semantic object';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
          blockBuilder: (
            BuildContext context,
            AnimatedMarkdownBlockContext block,
          ) {
            return const AnimatedMarkdownSelectable(
              plainText: source,
              child: SizedBox(
                key: ValueKey<String>('custom-object'),
                width: 180,
                height: 48,
              ),
            );
          },
        ),
      ),
    );

    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('custom-object')), findsOneWidget);
    expect(controller.value.selectedMarkdown, source);
    expect(_selectedPlainText(tester), contains(source));
  });

  testWidgets('text wrapper adapts SelectableText to source-backed selection', (
    WidgetTester tester,
  ) async {
    const String source = 'Custom partial selection';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
          blockBuilder: (
            BuildContext context,
            AnimatedMarkdownBlockContext block,
          ) {
            return const AnimatedMarkdownSelectable.text(
              plainText: source,
              child: SelectableText(
                source,
                style: TextStyle(fontSize: 20),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final RenderEditable editable = _descendantRenderObject<RenderEditable>(
      tester.renderObject<RenderObject>(find.byType(EditableText)),
    )!;
    final Offset start = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 7)).center,
    );
    final Offset end = editable.localToGlobal(
      editable.getLocalRectForCaret(const TextPosition(offset: 14)).center,
    );
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(controller.value.selectedMarkdown, 'partial');
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .textEditingValue
          .selection
          .isCollapsed,
      isTrue,
      reason: 'SelectableText must delegate to one Markdown selection layer.',
    );
  });

  testWidgets('fragment wrapper selects part of a composite custom object', (
    WidgetTester tester,
  ) async {
    const String source = 'Alpha Beta';
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
          blockBuilder: (
            BuildContext context,
            AnimatedMarkdownBlockContext block,
          ) {
            return const AnimatedMarkdownSelectable.fragments(
              plainText: source,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedMarkdownSelectionFragment(
                    plainText: 'Alpha ',
                    plainTextStart: 0,
                    child: Text(
                      'Alpha ',
                      key: ValueKey<String>('alpha-fragment'),
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                  AnimatedMarkdownSelectionFragment(
                    plainText: 'Beta',
                    plainTextStart: 6,
                    child: Text(
                      'Beta',
                      key: ValueKey<String>('beta-fragment'),
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final RenderParagraph alpha = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey<String>('alpha-fragment')),
    );
    final RenderParagraph beta = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey<String>('beta-fragment')),
    );
    final Offset start = alpha.localToGlobal(
      alpha.getOffsetForCaret(const TextPosition(offset: 2), Rect.zero) +
          Offset(0, alpha.size.height / 2),
    );
    final Offset end = beta.localToGlobal(
      beta.getOffsetForCaret(const TextPosition(offset: 2), Rect.zero) +
          Offset(0, beta.size.height / 2),
    );
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(controller.value.selectedMarkdown, 'pha Be');
  });

  testWidgets('fragment selection paints above an opaque custom background', (
    WidgetTester tester,
  ) async {
    const String source = 'Alpha Beta';
    const ValueKey<String> boundaryKey = ValueKey<String>('paint-boundary');
    const ValueKey<String> textKey = ValueKey<String>('paint-fragment');
    final AnimatedMarkdownSelectionController controller =
        AnimatedMarkdownSelectionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedStreamingMarkdown.fromMarkdown(
          markdown: source,
          enableSelection: true,
          selectionController: controller,
          blockBuilder: (
            BuildContext context,
            AnimatedMarkdownBlockContext block,
          ) {
            return const AnimatedMarkdownSelectable.fragments(
              plainText: source,
              selectionColor: Color(0xFF00FF00),
              child: RepaintBoundary(
                key: boundaryKey,
                child: ColoredBox(
                  color: Color(0xFFFF0000),
                  child: AnimatedMarkdownSelectionFragment(
                    plainText: source,
                    plainTextStart: 0,
                    child: Text(
                      source,
                      key: textKey,
                      style: TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 6);
    await tester.pump();

    final RenderParagraph paragraph =
        tester.renderObject<RenderParagraph>(find.byKey(textKey));
    final RenderRepaintBoundary boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final Rect spaceRect = MatrixUtils.transformRect(
      paragraph.getTransformTo(boundary),
      paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 5, extentOffset: 6),
          )
          .single
          .toRect(),
    );
    if (kIsWeb) {
      return;
    }
    final List<int> rgba = (await tester.runAsync<List<int>>(() async {
      final ui.Image image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final int x = spaceRect.center.dx.floor().clamp(0, image.width - 1);
        final int y = spaceRect.center.dy.floor().clamp(0, image.height - 1);
        final int pixel = (y * image.width + x) * 4;
        return <int>[
          bytes.getUint8(pixel),
          bytes.getUint8(pixel + 1),
          bytes.getUint8(pixel + 2),
          bytes.getUint8(pixel + 3),
        ];
      } finally {
        image.dispose();
      }
    }))!;

    expect(
      rgba,
      <int>[0, 255, 0, 255],
      reason: 'The fragment highlight must paint over the custom red card.',
    );
  });
}

String _selectedPlainText(WidgetTester tester) {
  final StringBuffer selected = StringBuffer();
  for (final Element element in find
      .byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_SelectableInlineTextProxy',
      )
      .evaluate()) {
    final Object? renderObject = element.renderObject;
    if (renderObject is Selectable) {
      selected.write(renderObject.getSelectedContent()?.plainText ?? '');
    }
  }
  return selected.toString();
}

T? _descendantRenderObject<T extends RenderObject>(RenderObject root) {
  if (root is T) {
    return root;
  }
  T? result;
  root.visitChildren((RenderObject child) {
    result ??= _descendantRenderObject<T>(child);
  });
  return result;
}
