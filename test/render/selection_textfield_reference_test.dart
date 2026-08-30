import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _surfaceSize = Size(360, 140);
const Offset _trajectoryStart = Offset(24, 18);
const Offset _trajectoryEnd = Offset(24, 148);

void main() {
  testWidgets('edge drag follows the multiline TextField scroll contract',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final _ScrollTrace textFieldTrace = await _traceTextField(tester);
    final _MarkdownTrace markdownTrace = await _traceMarkdown(tester);

    expect(textFieldTrace.firstMovingFrame, isNotNull);
    expect(markdownTrace.scroll.firstMovingFrame, isNotNull);
    expect(
      markdownTrace.scroll.firstMovingFrame!,
      lessThanOrEqualTo(textFieldTrace.firstMovingFrame! + 1),
      reason: 'Markdown auto-scroll may not start more than one frame after '
          'the TextField reference.',
    );
    expect(_isMonotonic(textFieldTrace.offsets), isTrue);
    expect(_isMonotonic(markdownTrace.scroll.offsets), isTrue);
    expect(markdownTrace.selection.hasSelection, isTrue);
    expect(
      markdownTrace.selection.selection.extentOffset,
      greaterThan(markdownTrace.selection.selection.baseOffset),
    );
    expect(
      markdownTrace.scroll.secondFrameAfterRelease,
      closeTo(markdownTrace.scroll.firstFrameAfterRelease, 0.01),
      reason: 'Markdown must not create fling or momentum after release.',
    );
  });
}

Future<_ScrollTrace> _traceTextField(WidgetTester tester) async {
  final ScrollController scrollController = ScrollController();
  final TextEditingController textController = TextEditingController(
    text: <String>[
      for (int index = 0; index < 40; index += 1)
        'Reference line $index keeps selection moving through the viewport.',
    ].join('\n'),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: TextField(
            controller: textController,
            scrollController: scrollController,
            expands: true,
            minLines: null,
            maxLines: null,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final _ScrollTrace trace = await _runTrajectory(tester, scrollController);

  await tester.pumpWidget(const SizedBox.shrink());
  scrollController.dispose();
  textController.dispose();
  return trace;
}

Future<_MarkdownTrace> _traceMarkdown(WidgetTester tester) async {
  final ScrollController scrollController = ScrollController();
  final AnimatedMarkdownSelectionController selectionController =
      AnimatedMarkdownSelectionController();
  final String markdown = <String>[
    for (int index = 0; index < 40; index += 1)
      'Reference line $index keeps selection moving through the viewport.',
  ].join('\n\n');

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: <Widget>[
            AnimatedStreamingMarkdown.fromMarkdown(
              markdown: markdown,
              padding: EdgeInsets.zero,
              tokenStaggerDelay: Duration.zero,
              tokenAnimationDuration: Duration.zero,
              enableSelection: true,
              selectionController: selectionController,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  final _ScrollTrace trace = await _runTrajectory(tester, scrollController);
  final AnimatedMarkdownSelectionValue selection = selectionController.value;

  await tester.pumpWidget(const SizedBox.shrink());
  scrollController.dispose();
  selectionController.dispose();
  return _MarkdownTrace(scroll: trace, selection: selection);
}

Future<_ScrollTrace> _runTrajectory(
  WidgetTester tester,
  ScrollController scrollController,
) async {
  final TestGesture gesture = await tester.startGesture(
    _trajectoryStart,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(_trajectoryEnd);

  final List<double> offsets = <double>[];
  int? firstMovingFrame;
  for (int frame = 0; frame < 30; frame += 1) {
    await tester.pump(const Duration(milliseconds: 16));
    offsets.add(scrollController.offset);
    if (firstMovingFrame == null && scrollController.offset > 0.01) {
      firstMovingFrame = frame;
    }
  }

  await gesture.up();
  await tester.pump(const Duration(milliseconds: 16));
  final double firstFrameAfterRelease = scrollController.offset;
  await tester.pump(const Duration(milliseconds: 32));
  final double secondFrameAfterRelease = scrollController.offset;

  return _ScrollTrace(
    firstMovingFrame: firstMovingFrame,
    offsets: offsets,
    firstFrameAfterRelease: firstFrameAfterRelease,
    secondFrameAfterRelease: secondFrameAfterRelease,
  );
}

bool _isMonotonic(List<double> values) {
  for (int index = 1; index < values.length; index += 1) {
    if (values[index] + 0.01 < values[index - 1]) {
      return false;
    }
  }
  return true;
}

class _ScrollTrace {
  const _ScrollTrace({
    required this.firstMovingFrame,
    required this.offsets,
    required this.firstFrameAfterRelease,
    required this.secondFrameAfterRelease,
  });

  final int? firstMovingFrame;
  final List<double> offsets;
  final double firstFrameAfterRelease;
  final double secondFrameAfterRelease;
}

class _MarkdownTrace {
  const _MarkdownTrace({required this.scroll, required this.selection});

  final _ScrollTrace scroll;
  final AnimatedMarkdownSelectionValue selection;
}
