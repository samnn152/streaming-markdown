import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:animated_streaming_markdown/streaming_markdown.dart';

import 'src/core/config/app_env.dart';
import 'src/features/chat/data/datasources/gemini_remote_data_source.dart';
import 'src/features/chat/data/repositories/chat_repository_impl.dart';
import 'src/features/chat/domain/usecases/stream_chat_answer_use_case.dart';
import 'src/features/chat/presentation/bloc/chat_bloc.dart';
import 'src/features/chat/presentation/pages/chat_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadEnv();

  runApp(const GeminiMarkdownDemoApp());
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
  const GeminiMarkdownDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatBloc>(
      create: (_) => ChatBloc(
        streamAnswerUseCase: _buildUseCase(),
        parserWorker: StreamingMarkdownParseWorker(),
        rope: RopeString(),
      )..add(const ChatStarted()),
      child: MaterialApp(
        title: 'Gemini Markdown Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A66C2)),
          useMaterial3: true,
        ),
        home: const _DualChatShowcasePage(),
      ),
    );
  }
}

class _DualChatShowcasePage extends StatefulWidget {
  const _DualChatShowcasePage();

  @override
  State<_DualChatShowcasePage> createState() => _DualChatShowcasePageState();
}

class _DualChatShowcasePageState extends State<_DualChatShowcasePage> {
  final TextEditingController _sharedQuestionController =
      TextEditingController();

  @override
  void dispose() {
    _sharedQuestionController.dispose();
    super.dispose();
  }

  void _submitSharedQuestion() {
    final String question = _sharedQuestionController.text.trim();
    if (question.isEmpty) {
      return;
    }
    context.read<ChatBloc>().add(ChatSubmitted(question: question));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Streaming Markdown Showcase')),
      body: SafeArea(
        child: BlocBuilder<ChatBloc, ChatState>(
          builder: (BuildContext context, ChatState state) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sharedQuestionController,
                          textInputAction: TextInputAction.send,
                          enabled: !state.isSubmitting,
                          onSubmitted: (_) => _submitSharedQuestion(),
                          decoration: const InputDecoration(
                            labelText: 'Câu hỏi chung cho 2 pane',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: state.isSubmitting
                            ? null
                            : _submitSharedQuestion,
                        child: state.isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Submit both'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final bool sideBySide = constraints.maxWidth >= 1000;
                          final Widget defaultPane = Expanded(
                            child: ChatPage(
                              tokenRenderInterval: const Duration(
                                milliseconds: 50,
                              ),
                              markdownTokenFadeInDuration: const Duration(
                                milliseconds: 300,
                              ),
                              markdownEnableSelection: true,
                              embedInScaffold: false,
                              showComposer: false,
                            ),
                          );
                          final Widget pinkPane = Expanded(
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.fromSeed(
                                  seedColor: const Color(0xFFE91E63),
                                ),
                              ),
                              child: ChatPage(
                                tokenRenderInterval: const Duration(
                                  milliseconds: 50,
                                ),
                                markdownTokenFadeInDuration: const Duration(
                                  milliseconds: 300,
                                ),
                                markdownEnableSelection: true,
                                embedInScaffold: false,
                                showComposer: false,
                                markdownTheme: const StreamingMarkdownThemeData(
                                  blockSpacing: 14,
                                  paragraphTextStyle: TextStyle(
                                    color: Color(0xFF4A1134),
                                    fontSize: 16,
                                  ),
                                  heading1TextStyle: TextStyle(
                                    color: Color(0xFFC2185B),
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  heading2TextStyle: TextStyle(
                                    color: Color(0xFFC2185B),
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  heading3TextStyle: TextStyle(
                                    color: Color(0xFFAD1457),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  linkTextStyle: TextStyle(
                                    color: Color(0xFFE91E63),
                                    decoration: TextDecoration.underline,
                                  ),
                                  inlineCodeTextStyle: TextStyle(
                                    color: Color(0xFFAD1457),
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                  inlineCodeBackgroundColor: Color(0xFFFCE4EC),
                                  codeBlockBackgroundColor: Color(0xFFFFF0F6),
                                  codeBlockHeaderBackgroundColor: Color(
                                    0xFFF8BBD0,
                                  ),
                                  codeBlockLanguageTextStyle: TextStyle(
                                    color: Color(0xFF880E4F),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  codeBlockTextStyle: TextStyle(
                                    color: Color(0xFF4A1134),
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                  quoteBackgroundColor: Color(0xFFFFF0F6),
                                  metadataBackgroundColor: Color(0xFFFFF0F6),
                                  metadataBorderColor: Color(0xFFF48FB1),
                                  metadataTextStyle: TextStyle(
                                    color: Color(0xFF6A1B4D),
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                  tableBorderColor: Color(0xFFF48FB1),
                                  tableHeaderBackgroundColor: Color(0xFFFCE4EC),
                                  thematicBreakColor: Color(0xFFF06292),
                                  imageErrorBackgroundColor: Color(0xFFFCE4EC),
                                  imageErrorTextStyle: TextStyle(
                                    color: Color(0xFF880E4F),
                                  ),
                                  selectionColor: Color(0x66E91E63),
                                ),
                                markdownCustomBlockBuilder: _pinkBlockBuilder,
                                markdownOnLinkTap: (String url) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Pink link tapped: $url'),
                                    ),
                                  );
                                },
                              ),
                            ),
                          );

                          if (sideBySide) {
                            return Row(
                              children: [
                                defaultPane,
                                const VerticalDivider(width: 1),
                                pinkPane,
                              ],
                            );
                          }

                          return Column(
                            children: [
                              defaultPane,
                              const Divider(height: 1),
                              pinkPane,
                            ],
                          );
                        },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget? _pinkBlockBuilder(
    BuildContext context,
    StreamingMarkdownBlockBuildContext block,
  ) {
    if (block.node.type == 'thematic_break') {
      return const Divider(height: 1, thickness: 2, color: Color(0xFFE91E63));
    }
    if (block.node.type == 'block_quote') {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF48FB1)),
        ),
        child: block.defaultWidget,
      );
    }
    return null;
  }
}
