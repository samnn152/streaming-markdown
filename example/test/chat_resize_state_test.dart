import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_example/src/features/chat/domain/models/chat_connection_settings.dart';
import 'package:streaming_markdown_example/src/features/chat/domain/repositories/chat_repository.dart';
import 'package:streaming_markdown_example/src/features/chat/domain/usecases/stream_chat_answer_use_case.dart';
import 'package:streaming_markdown_example/src/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:streaming_markdown_example/src/features/chat/presentation/pages/chat_page.dart';

void main() {
  testWidgets('responsive layout keeps assistant renderer selection state', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['text'] as String?;
        } else if (methodCall.method == 'writeRichText') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['plainText'] as String?;
        }
        return null;
      },
    );
    const MethodChannel richClipboardChannel = MethodChannel(
      'animated_streaming_markdown/clipboard',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      richClipboardChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'writeRichText') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['plainText'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        richClipboardChannel,
        null,
      );
    });

    final ChatConnectionSettings settings = ChatConnectionSettings.defaults(
      ChatProvider.ollama,
    );
    final ChatBloc bloc = ChatBloc(
      streamAnswerUseCase: StreamChatAnswerUseCase(_FixedAnswerRepository()),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider<ChatBloc>.value(
        value: bloc,
        child: MaterialApp(home: ChatPage(initialSettings: settings)),
      ),
    );
    bloc.add(ChatSubmitted(question: 'test', settings: settings));
    await tester.pump();
    for (int i = 0; i < 20; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .byKey(const ValueKey<String>('assistant_streaming_markdown_view'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.byKey(const ValueKey<String>('assistant_streaming_markdown_view')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    Finder assistantRegion() {
      return find.descendant(
        of: find.byKey(
          const ValueKey<String>('assistant_streaming_markdown_view'),
        ),
        matching: find.byType(SelectableRegion),
      );
    }

    final SelectableRegionState initialRegion =
        tester.state<SelectableRegionState>(assistantRegion());
    initialRegion.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    Actions.invoke(
      tester.element(assistantRegion()),
      CopySelectionTextIntent.copy,
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(clipboardText, 'Stable token response.');

    clipboardText = null;
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pump();

    Actions.invoke(
      tester.element(assistantRegion()),
      CopySelectionTextIntent.copy,
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(clipboardText, 'Stable token response.');
  });

  testWidgets('new messages keep completed assistant renderer state alive', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['text'] as String?;
        } else if (methodCall.method == 'writeRichText') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['plainText'] as String?;
        }
        return null;
      },
    );
    const MethodChannel richClipboardChannel = MethodChannel(
      'animated_streaming_markdown/clipboard',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      richClipboardChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'writeRichText') {
          final Map<dynamic, dynamic> data =
              methodCall.arguments! as Map<dynamic, dynamic>;
          clipboardText = data['plainText'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        richClipboardChannel,
        null,
      );
    });

    final ChatConnectionSettings settings = ChatConnectionSettings.defaults(
      ChatProvider.ollama,
    );
    final ChatBloc bloc = ChatBloc(
      streamAnswerUseCase: StreamChatAnswerUseCase(_FixedAnswerRepository()),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider<ChatBloc>.value(
        value: bloc,
        child: MaterialApp(home: ChatPage(initialSettings: settings)),
      ),
    );

    await _submitTurn(tester, bloc, settings, 'first', 2);
    final ChatMessage firstAssistant = bloc.state.messages.last;
    final Finder firstBubble = find.byKey(
      ValueKey<String>('assistant_markdown_${firstAssistant.id}'),
    );
    final Finder firstRenderer = find.descendant(
      of: firstBubble,
      matching: find.byKey(
        const ValueKey<String>('assistant_streaming_markdown_view'),
      ),
    );
    for (int frame = 0;
        frame < 20 && firstRenderer.evaluate().isEmpty;
        frame += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(firstRenderer, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    Finder composer() => find.byWidgetPredicate(
          (Widget widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Ask something...',
        );
    for (int frame = 0;
        frame < 30 && tester.widget<TextField>(composer()).enabled != true;
        frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<TextField>(composer()).enabled, isTrue);

    final Element originalRendererElement = tester.element(firstRenderer);
    Finder firstRegion() => find.descendant(
          of: firstBubble,
          matching: find.byType(SelectableRegion),
        );
    tester
        .state<SelectableRegionState>(firstRegion())
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    Actions.invoke(
      tester.element(firstRegion()),
      CopySelectionTextIntent.copy,
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(clipboardText, 'Stable token response.');

    for (int turn = 0; turn < 10; turn += 1) {
      await _submitTurn(
        tester,
        bloc,
        settings,
        'follow-up $turn',
        (turn + 2) * 2,
      );
      final Finder activeMessageList = find.byKey(
        const PageStorageKey<String>('chat_message_list'),
      );
      final ScrollableState activeScrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: activeMessageList,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      activeScrollable.position.jumpTo(
        activeScrollable.position.maxScrollExtent,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      for (int frame = 0;
          frame < 30 && tester.widget<TextField>(composer()).enabled != true;
          frame += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.widget<TextField>(composer()).enabled,
        isTrue,
        reason: 'Turn $turn must settle before the next message.',
      );
    }
    expect(
      tester.widget<TextField>(composer()).enabled,
      isTrue,
      reason: 'Every completed assistant render must eventually settle.',
    );

    final Finder messageList = find.byKey(
      const PageStorageKey<String>('chat_message_list'),
    );
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(of: messageList, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
    scrollable.position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 100));

    expect(firstRenderer, findsOneWidget);
    expect(
      identical(tester.element(firstRenderer), originalRendererElement),
      isTrue,
      reason: 'A completed message must not recreate its parser/animation.',
    );

    clipboardText = null;
    Actions.invoke(
      tester.element(firstRegion()),
      CopySelectionTextIntent.copy,
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(
      clipboardText,
      'Stable token response.',
      reason: 'Selection state must survive later messages and list recycling.',
    );
  });
}

Future<void> _submitTurn(
  WidgetTester tester,
  ChatBloc bloc,
  ChatConnectionSettings settings,
  String question,
  int expectedMessageCount,
) async {
  final Future<ChatState> completed = bloc.stream.firstWhere(
    (ChatState state) =>
        !state.isSubmitting && state.messages.length == expectedMessageCount,
  );
  bloc.add(ChatSubmitted(question: question, settings: settings));
  await tester.pump();
  await tester.runAsync(() => completed);
  await tester.pump(const Duration(milliseconds: 100));
}

final class _FixedAnswerRepository implements ChatRepository {
  @override
  Stream<String> streamAnswer(ChatCompletionRequest request) async* {
    yield 'Stable token response.';
  }

  @override
  void dispose() {}
}
