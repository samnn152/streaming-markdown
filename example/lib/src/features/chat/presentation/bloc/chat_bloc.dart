import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models/chat_connection_settings.dart';
import '../../domain/usecases/stream_chat_answer_use_case.dart';

sealed class ChatEvent {
  const ChatEvent();
}

final class ChatStarted extends ChatEvent {
  const ChatStarted();
}

final class ChatSubmitted extends ChatEvent {
  const ChatSubmitted({required this.question, required this.settings});

  final String question;
  final ChatConnectionSettings settings;
}

final class ChatCleared extends ChatEvent {
  const ChatCleared();
}

final class ChatState {
  const ChatState({
    required this.isSubmitting,
    required this.status,
    required this.messages,
  });

  const ChatState.initial()
      : this(
          isSubmitting: false,
          status: 'Choose a provider and send a message.',
          messages: const <ChatMessage>[],
        );

  final bool isSubmitting;
  final String status;
  final List<ChatMessage> messages;

  ChatState copyWith({
    bool? isSubmitting,
    String? status,
    List<ChatMessage>? messages,
  }) {
    return ChatState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      status: status ?? this.status,
      messages: messages ?? this.messages,
    );
  }
}

final class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({required StreamChatAnswerUseCase streamAnswerUseCase})
      : _streamAnswerUseCase = streamAnswerUseCase,
        super(const ChatState.initial()) {
    on<ChatStarted>(_onStarted);
    on<ChatSubmitted>(_onSubmitted);
    on<ChatCleared>(_onCleared);
  }

  final StreamChatAnswerUseCase _streamAnswerUseCase;
  int _nextTurnSequence = 0;

  void _onStarted(ChatStarted event, Emitter<ChatState> emit) {
    emit(state.copyWith(status: 'Choose a provider and send a message.'));
  }

  void _onCleared(ChatCleared event, Emitter<ChatState> emit) {
    if (state.isSubmitting) {
      return;
    }
    emit(const ChatState.initial());
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

    final String turnId =
        '${DateTime.now().microsecondsSinceEpoch}_${_nextTurnSequence++}';
    final List<ChatMessage> nextMessages = <ChatMessage>[
      ...state.messages,
      ChatMessage(
        id: 'user_$turnId',
        role: 'user',
        content: question,
        complete: true,
      ),
      ChatMessage(id: 'assistant_$turnId', role: 'assistant', content: ''),
    ];
    emit(
      state.copyWith(
        isSubmitting: true,
        status: 'Calling ${event.settings.provider.label}...',
        messages: nextMessages,
      ),
    );

    final int assistantIndex = nextMessages.length - 1;
    final StringBuffer answer = StringBuffer();

    try {
      await for (final String chunk in _streamAnswerUseCase(
        ChatCompletionRequest(
          settings: event.settings,
          messages: nextMessages.take(assistantIndex).toList(growable: false),
        ),
      )) {
        if (chunk.isEmpty) {
          continue;
        }
        answer.write(chunk);
        final List<ChatMessage> updatedMessages = List<ChatMessage>.from(
          state.messages,
        );
        updatedMessages[assistantIndex] = updatedMessages[assistantIndex]
            .copyWith(content: answer.toString());
        emit(
          state.copyWith(
            messages: updatedMessages,
            status: 'Streaming ${event.settings.provider.label}...',
          ),
        );
      }

      emit(
        state.copyWith(
          isSubmitting: false,
          status: answer.isEmpty ? 'No answer content returned.' : 'Ready.',
          messages: _completeAssistantMessage(state.messages, assistantIndex),
        ),
      );
    } catch (error) {
      final List<ChatMessage> updatedMessages = List<ChatMessage>.from(
        state.messages,
      );
      updatedMessages[assistantIndex] =
          updatedMessages[assistantIndex].copyWith(
        content: 'Request failed:\n\n```text\n$error\n```',
        complete: true,
      );
      emit(
        state.copyWith(
          isSubmitting: false,
          status: 'Request failed.',
          messages: updatedMessages,
        ),
      );
    }
  }

  List<ChatMessage> _completeAssistantMessage(
    List<ChatMessage> messages,
    int assistantIndex,
  ) {
    final List<ChatMessage> updatedMessages = List<ChatMessage>.from(messages);
    if (assistantIndex < 0 || assistantIndex >= updatedMessages.length) {
      return updatedMessages;
    }
    updatedMessages[assistantIndex] = updatedMessages[assistantIndex].copyWith(
      complete: true,
    );
    return updatedMessages;
  }

  @override
  Future<void> close() {
    _streamAnswerUseCase.dispose();
    return super.close();
  }
}
