import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';

import '../../domain/usecases/stream_chat_answer_use_case.dart';

sealed class ChatEvent {
  const ChatEvent();
}

final class ChatStarted extends ChatEvent {
  const ChatStarted();
}

final class ChatSubmitted extends ChatEvent {
  const ChatSubmitted({required this.question});

  final String question;
}

final class ChatState {
  const ChatState({
    required this.isWorkerReady,
    required this.isSubmitting,
    required this.status,
    required this.answerMarkdown,
    required this.answerNodes,
    required this.streamedTokens,
  });

  const ChatState.initial()
    : this(
        isWorkerReady: false,
        isSubmitting: false,
        status: 'Nhập câu hỏi rồi bấm Submit.',
        answerMarkdown: '',
        answerNodes: const <MarkdownRenderNode>[],
        streamedTokens: const <String>[],
      );

  final bool isWorkerReady;
  final bool isSubmitting;
  final String status;
  final String answerMarkdown;
  final List<MarkdownRenderNode> answerNodes;
  final List<String> streamedTokens;

  ChatState copyWith({
    bool? isWorkerReady,
    bool? isSubmitting,
    String? status,
    String? answerMarkdown,
    List<MarkdownRenderNode>? answerNodes,
    List<String>? streamedTokens,
  }) {
    return ChatState(
      isWorkerReady: isWorkerReady ?? this.isWorkerReady,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      status: status ?? this.status,
      answerMarkdown: answerMarkdown ?? this.answerMarkdown,
      answerNodes: answerNodes ?? this.answerNodes,
      streamedTokens: streamedTokens ?? this.streamedTokens,
    );
  }
}

final class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    required StreamChatAnswerUseCase streamAnswerUseCase,
    required StreamingMarkdownParseWorker parserWorker,
    required RopeString rope,
  }) : _streamAnswerUseCase = streamAnswerUseCase,
       _parserWorker = parserWorker,
       _rope = rope,
       super(const ChatState.initial()) {
    on<ChatStarted>(_onStarted);
    on<ChatSubmitted>(_onSubmitted);
  }

  final StreamChatAnswerUseCase _streamAnswerUseCase;
  final StreamingMarkdownParseWorker _parserWorker;
  final RopeString _rope;

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    try {
      await _parserWorker.start();
      emit(
        state.copyWith(
          isWorkerReady: true,
          status: 'Nhập câu hỏi rồi bấm Submit.',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isWorkerReady: false,
          status: 'Không khởi tạo được markdown worker: $error',
        ),
      );
    }
  }

  Future<void> _onSubmitted(
    ChatSubmitted event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isSubmitting) {
      return;
    }

    final String question = event.question.trim();
    if (question.isEmpty) {
      return;
    }

    if (!state.isWorkerReady) {
      emit(state.copyWith(status: 'Markdown worker chưa sẵn sàng.'));
      return;
    }

    emit(
      state.copyWith(
        isSubmitting: true,
        status: 'Đang gọi Gemini...',
        answerMarkdown: '',
        answerNodes: const <MarkdownRenderNode>[],
        streamedTokens: const <String>[],
      ),
    );

    _rope.clear();

    try {
      await _parserWorker.request(op: 'set', text: '', includeNodes: true);

      int chunkCount = 0;
      await for (final String chunk in _streamAnswerUseCase(question)) {
        if (chunk.isEmpty) {
          continue;
        }

        chunkCount += 1;
        _rope.append(chunk);
        final StreamingMarkdownParseResult parseResult = await _parserWorker
            .request(op: 'append', text: chunk, includeNodes: true);
        final List<String> nextTokens = List<String>.from(state.streamedTokens)
          ..addAll(_tokenizeChunk(chunk));

        emit(
          state.copyWith(
            answerMarkdown: _rope.toString(),
            answerNodes: parseResult.renderNodes,
            streamedTokens: nextTokens,
            status: 'Đang nhận dữ liệu... ($chunkCount chunks)',
          ),
        );
      }

      final String finalStatus = _rope.isEmpty
          ? 'Không nhận được nội dung trả lời từ Gemini.'
          : 'Đã nhận câu trả lời.';
      emit(state.copyWith(isSubmitting: false, status: finalStatus));
    } catch (error) {
      emit(
        state.copyWith(isSubmitting: false, status: 'Gọi API thất bại: $error'),
      );
    }
  }

  @override
  Future<void> close() {
    _parserWorker.dispose();
    _streamAnswerUseCase.dispose();
    return super.close();
  }

  Iterable<String> _tokenizeChunk(String chunk) sync* {
    for (final RegExpMatch match in RegExp(r'\S+').allMatches(chunk)) {
      final String token = match.group(0) ?? '';
      if (token.isNotEmpty) {
        yield token;
      }
    }
  }
}
