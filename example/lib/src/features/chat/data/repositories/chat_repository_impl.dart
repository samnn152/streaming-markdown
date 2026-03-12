import '../../domain/repositories/chat_repository.dart';
import '../datasources/gemini_remote_data_source.dart';

final class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({required GeminiRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  final GeminiRemoteDataSource _remoteDataSource;

  @override
  Stream<String> streamAnswer(String question) {
    return _remoteDataSource.streamAnswer(question);
  }

  @override
  void dispose() {
    _remoteDataSource.dispose();
  }
}
