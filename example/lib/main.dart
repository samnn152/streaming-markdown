import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'src/core/config/app_env.dart';
import 'src/features/chat/data/datasources/chat_remote_data_source.dart';
import 'src/features/chat/data/repositories/chat_repository_impl.dart';
import 'src/features/chat/domain/usecases/stream_chat_answer_use_case.dart';
import 'src/features/chat/presentation/bloc/chat_bloc.dart';
import 'src/features/chat/presentation/pages/chat_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadEnv();

  runApp(const MarkdownChatApp());
}

Future<void> _loadEnv() async {
  if (kIsWeb) {
    return;
  }
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Fallback to --dart-define values when .env is unavailable.
  }
}

StreamChatAnswerUseCase _buildUseCase() {
  final ChatRemoteDataSource remoteDataSource = ChatRemoteDataSource();
  final ChatRepositoryImpl repository = ChatRepositoryImpl(
    remoteDataSource: remoteDataSource,
  );
  return StreamChatAnswerUseCase(repository);
}

class MarkdownChatApp extends StatelessWidget {
  const MarkdownChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatBloc>(
      create: (_) => ChatBloc(streamAnswerUseCase: _buildUseCase())
        ..add(const ChatStarted()),
      child: MaterialApp(
        title: 'Streaming Markdown Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
          useMaterial3: true,
        ),
        home: ChatPage(
          initialSettings: AppEnv.initialChatSettings,
          markdownTheme: const AnimatedMarkdownThemeData(
            blockSpacing: 14,
            codeBlockBackgroundColor: Color(0xFF0F172A),
            codeBlockHeaderBackgroundColor: Color(0xFF1E293B),
            codeBlockTextStyle: TextStyle(
              color: Color(0xFFE2E8F0),
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
            ),
            codeBlockLanguageTextStyle: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            inlineCodeBackgroundColor: Color(0xFFEFF6FF),
            inlineCodeTextStyle: TextStyle(
              color: Color(0xFF1D4ED8),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            selectionColor: Color(0x663B82F6),
          ),
        ),
      ),
    );
  }
}
