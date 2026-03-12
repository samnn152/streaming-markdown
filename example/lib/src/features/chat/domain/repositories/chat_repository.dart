abstract interface class ChatRepository {
  Stream<String> streamAnswer(String question);

  void dispose();
}
