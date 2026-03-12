import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

import '../bloc/chat_bloc.dart';

enum _TokenRenderCommand { none, completeNow }

// Flutter SDK in this repo exposes Durations.short1 (50ms), used as
// compatibility default for "extraShort1".
const Duration _kDefaultTokenRenderInterval = Durations.short1;

final class TokenRenderController extends ChangeNotifier {
  _TokenRenderCommand _pendingCommand = _TokenRenderCommand.none;

  /// Skip animation and immediately render all currently queued tokens.
  void completeNow() {
    _pendingCommand = _TokenRenderCommand.completeNow;
    notifyListeners();
  }

  _TokenRenderCommand _takePendingCommand() {
    final _TokenRenderCommand command = _pendingCommand;
    _pendingCommand = _TokenRenderCommand.none;
    return command;
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    this.tokenRenderInterval = _kDefaultTokenRenderInterval,
    this.markdownTokenFadeInRelativeToDelay = 1,
    this.markdownTokenFadeInDuration,
    this.markdownEnableSelection = false,
    this.onTokenRenderEnd,
    this.tokenRenderController,
    super.key,
  });

  final Duration tokenRenderInterval;
  final double markdownTokenFadeInRelativeToDelay;
  final Duration? markdownTokenFadeInDuration;
  final bool markdownEnableSelection;

  /// Called when UI has rendered all currently available server content.
  /// [forced] is true when completion is triggered by [TokenRenderController].
  final ValueChanged<bool>? onTokenRenderEnd;
  final TokenRenderController? tokenRenderController;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _tokenScrollController = ScrollController();
  final Queue<String> _pendingSegments = Queue<String>();
  final StreamingMarkdownParseWorker _renderWorker =
      StreamingMarkdownParseWorker();
  final RopeString _displayRope = RopeString();

  List<String> _displayedTokens = <String>[];
  List<MarkdownRenderNode> _displayedAnswerNodes = <MarkdownRenderNode>[];
  String _sourceMarkdown = '';
  String _displayedMarkdown = '';
  int _sourceTokenCount = 0;

  bool _isSubmitting = false;
  bool _didNotifyRenderEnd = false;
  bool _renderWorkerReady = false;
  bool _isPumping = false;
  bool _forceCompleteRequested = false;

  @override
  void initState() {
    super.initState();
    widget.tokenRenderController?.addListener(_onExternalRenderCommand);
    unawaited(_bootstrapRenderWorker());
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tokenRenderController == widget.tokenRenderController) {
      return;
    }
    oldWidget.tokenRenderController?.removeListener(_onExternalRenderCommand);
    widget.tokenRenderController?.addListener(_onExternalRenderCommand);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _tokenScrollController.dispose();
    widget.tokenRenderController?.removeListener(_onExternalRenderCommand);
    _renderWorker.dispose();
    super.dispose();
  }

  Future<void> _bootstrapRenderWorker() async {
    try {
      await _renderWorker.start();
      List<MarkdownRenderNode> nodes = <MarkdownRenderNode>[];
      if (!_displayRope.isEmpty) {
        final StreamingMarkdownParseResult parseResult = await _renderWorker
            .request(
              op: 'set',
              text: _displayRope.toString(),
              includeNodes: true,
            );
        nodes = parseResult.renderNodes;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _renderWorkerReady = true;
        _displayedAnswerNodes = nodes;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _renderWorkerReady = false;
      });
    }
  }

  void _submit() {
    context.read<ChatBloc>().add(
      ChatSubmitted(question: _questionController.text),
    );
  }

  // Decision 1: source markdown is always server output.
  String _sourceMarkdownFromServer(ChatState state) {
    return state.answerMarkdown;
  }

  // Decision 2: visible markdown/tokens are UI-delayed.
  void _onBlocStateUpdated(ChatState state) {
    _isSubmitting = state.isSubmitting;
    _syncDelayedRender(_sourceMarkdownFromServer(state));
  }

  void _onExternalRenderCommand() {
    final _TokenRenderCommand command =
        widget.tokenRenderController?._takePendingCommand() ??
        _TokenRenderCommand.none;
    if (command != _TokenRenderCommand.completeNow) {
      return;
    }

    if (_isPumping) {
      _forceCompleteRequested = true;
      return;
    }
    unawaited(_flushPendingSegments(forced: true));
  }

  void _syncDelayedRender(String incomingMarkdown) {
    if (incomingMarkdown.isEmpty) {
      _resetRenderState();
      return;
    }

    if (_sourceMarkdown.isNotEmpty &&
        !incomingMarkdown.startsWith(_sourceMarkdown)) {
      _resetRenderState();
    }

    if (incomingMarkdown.length < _sourceMarkdown.length) {
      _resetRenderState();
    }

    if (incomingMarkdown.length > _sourceMarkdown.length) {
      final String delta = incomingMarkdown.substring(_sourceMarkdown.length);
      _sourceMarkdown = incomingMarkdown;
      _sourceTokenCount += _tokenizeChunk(delta).length;
      _pendingSegments.addAll(_splitIntoRenderSegments(delta));
      _didNotifyRenderEnd = false;

      if (widget.tokenRenderInterval <= Duration.zero) {
        unawaited(_flushPendingSegments(forced: false));
      } else {
        _startPump();
      }
      return;
    }

    _maybeNotifyRenderEnd(forced: false);
  }

  Iterable<String> _splitIntoRenderSegments(String text) sync* {
    for (final RegExpMatch match in RegExp(r'\S+\s*|\s+').allMatches(text)) {
      final String segment = match.group(0) ?? '';
      if (segment.isNotEmpty) {
        yield segment;
      }
    }
  }

  void _startPump() {
    if (_isPumping) {
      return;
    }
    _isPumping = true;
    unawaited(_pumpSegments());
  }

  Future<void> _pumpSegments() async {
    try {
      while (mounted) {
        if (_forceCompleteRequested) {
          _forceCompleteRequested = false;
          await _flushPendingSegments(forced: true);
          break;
        }

        if (_pendingSegments.isEmpty) {
          break;
        }

        final String segment = _pendingSegments.removeFirst();
        await _appendRenderedSegment(segment);

        if (_pendingSegments.isNotEmpty &&
            widget.tokenRenderInterval > Duration.zero) {
          await Future<void>.delayed(widget.tokenRenderInterval);
        }
      }
    } finally {
      _isPumping = false;
      _maybeNotifyRenderEnd(forced: false);
    }
  }

  Future<void> _appendRenderedSegment(String segment) async {
    _displayRope.append(segment);

    List<MarkdownRenderNode> nextNodes = _displayedAnswerNodes;
    if (_renderWorkerReady) {
      try {
        final StreamingMarkdownParseResult parseResult = await _renderWorker
            .request(op: 'append', text: segment, includeNodes: true);
        nextNodes = parseResult.renderNodes;
      } catch (_) {
        nextNodes = _displayedAnswerNodes;
      }
    }

    final List<String> newTokens = _tokenizeChunk(segment);

    if (!mounted) {
      return;
    }
    setState(() {
      _displayedMarkdown = _displayRope.toString();
      _displayedAnswerNodes = nextNodes;
      if (newTokens.isNotEmpty) {
        _displayedTokens = <String>[..._displayedTokens, ...newTokens];
      }
    });
    _scrollTokensToEnd();
  }

  Future<void> _flushPendingSegments({required bool forced}) async {
    if (_pendingSegments.isNotEmpty) {
      final String remaining = _pendingSegments.join();
      _pendingSegments.clear();
      await _appendRenderedSegment(remaining);
    }
    _maybeNotifyRenderEnd(forced: forced);
  }

  void _resetRenderState() {
    _pendingSegments.clear();
    _sourceMarkdown = '';
    _displayRope.clear();
    _displayedMarkdown = '';
    _displayedTokens = <String>[];
    _sourceTokenCount = 0;
    _displayedAnswerNodes = <MarkdownRenderNode>[];
    _forceCompleteRequested = false;
    _didNotifyRenderEnd = false;

    if (mounted) {
      setState(() {});
    }

    if (_renderWorkerReady) {
      unawaited(_renderWorker.request(op: 'set', text: '', includeNodes: true));
    }
  }

  void _maybeNotifyRenderEnd({required bool forced}) {
    if (_didNotifyRenderEnd) {
      return;
    }

    final bool finishedCurrentBuffer =
        _pendingSegments.isEmpty && _displayedMarkdown == _sourceMarkdown;
    if (!finishedCurrentBuffer) {
      return;
    }
    if (!forced && _isSubmitting) {
      // UI rendered everything currently available, but server is still streaming.
      // Keep waiting for new content.
      return;
    }

    _didNotifyRenderEnd = true;
    widget.onTokenRenderEnd?.call(forced);
  }

  List<String> _tokenizeChunk(String chunk) {
    return RegExp(r'\S+')
        .allMatches(chunk)
        .map((RegExpMatch match) => match.group(0) ?? '')
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
  }

  void _scrollTokensToEnd() {
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
        _onBlocStateUpdated(state);
      },
      builder: (BuildContext context, ChatState state) {
        final Widget answerArea;
        if (_displayedAnswerNodes.isNotEmpty) {
          answerArea = StreamingMarkdownRenderView(
            nodes: _displayedAnswerNodes,
            allowUnclosedInlineDelimiters: true,
            tokenArrivalDelay: widget.tokenRenderInterval,
            tokenFadeInRelativeToDelay:
                widget.markdownTokenFadeInRelativeToDelay,
            tokenFadeInDuration: widget.markdownTokenFadeInDuration,
            enableTextSelection: widget.markdownEnableSelection,
          );
        } else if (_displayedMarkdown.isNotEmpty) {
          answerArea = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_displayedMarkdown),
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
                    .clamp(90, 170)
                    .toDouble();

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
                                'Streaming Tokens (${_displayedTokens.length}/$_sourceTokenCount)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: _displayedTokens.isEmpty
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
                                      itemCount: _displayedTokens.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 8),
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                            final String token =
                                                _displayedTokens[index];
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
