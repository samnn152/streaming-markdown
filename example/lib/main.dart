import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

import 'src/core/config/app_env.dart';
import 'src/features/chat/data/datasources/gemini_remote_data_source.dart';
import 'src/features/chat/data/repositories/chat_repository_impl.dart';
import 'src/features/chat/domain/usecases/stream_chat_answer_use_case.dart';
import 'src/features/chat/presentation/bloc/chat_bloc.dart';
import 'src/features/chat/presentation/pages/chat_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadEnv();

  final StreamChatAnswerUseCase streamAnswerUseCase = _buildUseCase();
  runApp(GeminiMarkdownDemoApp(streamAnswerUseCase: streamAnswerUseCase));
}

Future<void> _loadEnv() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Fallback to --dart-define values when .env is unavailable.
  }
}

StreamChatAnswerUseCase _buildUseCase() {
  final GeminiRemoteDataSource remoteDataSource = GeminiRemoteDataSource(
    apiKey: AppEnv.geminiApiKey,
    model: AppEnv.geminiModel,
  );
  final ChatRepositoryImpl repository = ChatRepositoryImpl(
    remoteDataSource: remoteDataSource,
  );
  return StreamChatAnswerUseCase(repository);
}

class GeminiMarkdownDemoApp extends StatelessWidget {
  const GeminiMarkdownDemoApp({required this.streamAnswerUseCase, super.key});

  final StreamChatAnswerUseCase streamAnswerUseCase;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatBloc>(
      create: (_) => ChatBloc(
        streamAnswerUseCase: streamAnswerUseCase,
        parserWorker: StreamingMarkdownParseWorker(),
        rope: RopeString(),
      )..add(const ChatStarted()),
      child: MaterialApp(
        title: 'Gemini Markdown Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A66C2)),
          useMaterial3: true,
        ),
        home: const ChatPage(),
      ),
    );
  }
}
