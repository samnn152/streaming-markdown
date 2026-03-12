import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

import '../bloc/chat_bloc.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _tokenScrollController = ScrollController();
  int _lastTokenCount = 0;

  @override
  void dispose() {
    _questionController.dispose();
    _tokenScrollController.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<ChatBloc>().add(
      ChatSubmitted(question: _questionController.text),
    );
  }

  void _maybeScrollTokenList(int newCount) {
    if (newCount <= _lastTokenCount) {
      _lastTokenCount = newCount;
      return;
    }
    _lastTokenCount = newCount;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tokenScrollController.hasClients) {
        return;
      }
      _tokenScrollController.animateTo(
        _tokenScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatBloc, ChatState>(
      listener: (BuildContext context, ChatState state) {
        _maybeScrollTokenList(state.streamedTokens.length);
      },
      builder: (BuildContext context, ChatState state) {
        final Widget answerArea;
        if (state.answerNodes.isNotEmpty) {
          answerArea = StreamingMarkdownRenderView(nodes: state.answerNodes);
        } else if (state.answerMarkdown.isNotEmpty) {
          answerArea = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(state.answerMarkdown),
          );
        } else if (state.isSubmitting) {
          answerArea = const Center(child: CircularProgressIndicator());
        } else {
          answerArea = const Center(child: Text('Chưa có câu trả lời.'));
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Gemini Markdown Demo')),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double tokenPanelHeight = (constraints.maxHeight / 6)
                    .clamp(90, 170);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _questionController,
                              textInputAction: TextInputAction.send,
                              enabled: !state.isSubmitting,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Câu hỏi',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: state.isSubmitting ? null : _submit,
                            child: state.isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Submit'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          state.status,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(child: answerArea),
                    const Divider(height: 1),
                    SizedBox(
                      height: tokenPanelHeight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'Streaming Tokens (${state.streamedTokens.length})',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: state.streamedTokens.isEmpty
                                  ? const Center(
                                      child: Text('Chưa có token nào.'),
                                    )
                                  : ListView.separated(
                                      controller: _tokenScrollController,
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      itemCount: state.streamedTokens.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 8),
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                            final String token =
                                                state.streamedTokens[index];
                                            return DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                child: Text(
                                                  token,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            );
                                          },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
