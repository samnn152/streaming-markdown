import '../../domain/repositories/chat_repository.dart';
import '../../domain/models/chat_connection_settings.dart';
import '../datasources/chat_remote_data_source.dart';

final class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({required ChatRemoteDataSource remoteDataSource})
      : _remoteDataSource = remoteDataSource;

  final ChatRemoteDataSource _remoteDataSource;

  @override
  Stream<String> streamAnswer(ChatCompletionRequest request) {
    return _remoteDataSource.streamAnswer(request);
  }

  @override
  void dispose() {
    _remoteDataSource.dispose();
  }
}
