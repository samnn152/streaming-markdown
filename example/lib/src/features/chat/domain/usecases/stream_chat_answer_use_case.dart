import '../repositories/chat_repository.dart';

final class StreamChatAnswerUseCase {
  StreamChatAnswerUseCase(this._repository);

  final ChatRepository _repository;

  Stream<String> call(String question) {
    return _repository.streamAnswer(question);
  }

  void dispose() {
    _repository.dispose();
  }
}
