import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

void main() {
  runApp(const MarkdownCasesDemoApp());
}

class MarkdownCasesDemoApp extends StatelessWidget {
  const MarkdownCasesDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markdown Cases Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A68),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A68),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MarkdownCasesDemoPage(),
    );
  }
}

class MarkdownCasesDemoPage extends StatefulWidget {
  const MarkdownCasesDemoPage({super.key});

  @override
  State<MarkdownCasesDemoPage> createState() => _MarkdownCasesDemoPageState();
}

class _MarkdownCasesDemoPageState extends State<MarkdownCasesDemoPage> {
  static const int _streamChunkLength = 28;
  static const Duration _streamChunkDelay = Duration(milliseconds: 110);

  final MarkdownStreamParser _worker = MarkdownStreamParser();
  final GlobalKey _workspaceKey = GlobalKey();

  List<MarkdownBlock> _nodes = const <MarkdownBlock>[];
  MarkdownParseResult? _result;
  int _selectedCase = -1;
  bool _workerStarted = false;
  bool _loading = true;
  bool _renderPaused = false;
  bool _showSource = false;
  bool _debugTokens = false;
  int _selectedTokenAnimation = 0;
  String? _error;
  int _streamedCharacters = 0;
  int _totalCharacters = 0;
  int _renderGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_startWorker());
  }

  @override
  void dispose() {
    _renderGeneration += 1;
    _worker.dispose();
    super.dispose();
  }

  Future<void> _startWorker() async {
    try {
      await _worker.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _workerStarted = true;
      });
      await _renderActiveMarkdown();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _renderActiveMarkdown({bool streamMarkdown = true}) async {
    if (!_workerStarted) {
      return;
    }

    final int generation = ++_renderGeneration;
    final String markdown = _activeMarkdown;

    setState(() {
      _loading = true;
      _renderPaused = false;
      _error = null;
      _streamedCharacters = streamMarkdown ? 0 : markdown.length;
      _totalCharacters = markdown.length;
      if (streamMarkdown) {
        _nodes = const <MarkdownBlock>[];
        _result = null;
      }
    });

    try {
      if (streamMarkdown) {
        await _requestParse('set', '');
        for (final String chunk in _chunkMarkdown(markdown)) {
          if (!mounted || generation != _renderGeneration) {
            return;
          }
          final MarkdownParseResult result = await _requestParse(
            'append',
            chunk,
          );
          if (!mounted || generation != _renderGeneration) {
            return;
          }
          setState(() {
            _nodes = result.blocks;
            _result = result;
            _streamedCharacters += chunk.length;
          });
          await Future<void>.delayed(_streamChunkDelay);
        }
        if (!mounted || generation != _renderGeneration) {
          return;
        }
        setState(() {
          _loading = false;
          _streamedCharacters = markdown.length;
        });
        return;
      }

      final MarkdownParseResult result = await _requestParse('set', markdown);
      if (!mounted || generation != _renderGeneration) {
        return;
      }
      setState(() {
        _nodes = result.blocks;
        _result = result;
        _loading = false;
        _streamedCharacters = markdown.length;
      });
    } catch (error) {
      if (!mounted || generation != _renderGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<MarkdownParseResult> _requestParse(String op, String text) {
    return op == 'append' ? _worker.append(text) : _worker.replace(text);
  }

  Iterable<String> _chunkMarkdown(String markdown) sync* {
    var index = 0;
    while (index < markdown.length) {
      final int desiredBreak = index + _streamChunkLength;
      final int searchStart = desiredBreak > markdown.length
          ? markdown.length
          : desiredBreak;
      final int nextBreak = markdown.indexOf(RegExp(r'[\s>]'), searchStart);
      final int end = nextBreak == -1
          ? markdown.length
          : (nextBreak + 1).clamp(index + 1, markdown.length);
      yield markdown.substring(index, end);
      index = end;
    }
  }

  String get _activeMarkdown {
    if (_selectedCase < 0) {
      return _allCasesMarkdown;
    }
    return _displayMarkdownCases[_selectedCase].markdown;
  }

  String get _visibleMarkdown {
    final String markdown = _activeMarkdown;
    if (_streamedCharacters >= markdown.length) {
      return markdown;
    }
    if (_streamedCharacters <= 0) {
      return '';
    }
    return markdown.substring(0, _streamedCharacters);
  }

  String get _activeTitle {
    if (_selectedCase < 0) {
      return 'All supported cases';
    }
    return _displayMarkdownCases[_selectedCase].title;
  }

  void _selectCase(int index) {
    if (_selectedCase == index) {
      return;
    }
    setState(() {
      _selectedCase = index;
    });
    unawaited(_renderActiveMarkdown());
  }

  void _toggleSource() {
    setState(() {
      _showSource = !_showSource;
    });
  }

  void _toggleDebugTokens() {
    setState(() {
      _debugTokens = !_debugTokens;
    });
    unawaited(_renderActiveMarkdown());
  }

  void _selectTokenAnimation(int index) {
    if (_selectedTokenAnimation == index) {
      return;
    }
    setState(() {
      _selectedTokenAnimation = index;
    });
    unawaited(_renderActiveMarkdown());
  }

  void _toggleRenderPaused() {
    setState(() {
      _renderPaused = !_renderPaused;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_activeTitle),
        actions: [
          IconButton(
            tooltip: 'Replay stream',
            icon: const Icon(Icons.play_arrow_outlined),
            onPressed: _loading
                ? null
                : () => unawaited(_renderActiveMarkdown()),
          ),
          IconButton(
            tooltip: _renderPaused ? 'Resume render' : 'Pause render',
            icon: Icon(
              _renderPaused
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline,
            ),
            onPressed: _nodes.isEmpty ? null : _toggleRenderPaused,
          ),
          IconButton(
            tooltip: _showSource ? 'Hide source' : 'Show source',
            icon: Icon(
              _showSource
                  ? Icons.vertical_split_outlined
                  : Icons.article_outlined,
            ),
            onPressed: _toggleSource,
          ),
          IconButton(
            tooltip: _debugTokens
                ? 'Hide token merge trace'
                : 'Trace token merge',
            icon: Icon(
              _debugTokens
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: _toggleDebugTokens,
          ),
          PopupMenuButton<int>(
            tooltip: 'Token animation style',
            icon: const Icon(Icons.auto_awesome_motion_outlined),
            initialValue: _selectedTokenAnimation,
            onSelected: _selectTokenAnimation,
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry<int>>[
                for (int i = 0; i < _tokenAnimationPresets.length; i++)
                  PopupMenuItem<int>(
                    value: i,
                    child: Text(_tokenAnimationPresets[i].name),
                  ),
              ];
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 980;
            final Widget caseList = _CaseList(
              selectedIndex: _selectedCase,
              onSelected: _selectCase,
            );
            final Widget workspace = _Workspace(
              key: _workspaceKey,
              nodes: _nodes,
              source: _visibleMarkdown,
              result: _result,
              error: _error,
              loading: _loading,
              renderPaused: _renderPaused,
              streamedCharacters: _streamedCharacters,
              totalCharacters: _totalCharacters,
              showSource: _showSource,
              debugTokens: _debugTokens,
              tokenAnimationBuilder:
                  _tokenAnimationPresets[_selectedTokenAnimation].builder,
              tokenAnimationName:
                  _tokenAnimationPresets[_selectedTokenAnimation].name,
              onLinkTap: _showLinkSnackBar,
            );

            if (wide) {
              return Row(
                children: [
                  SizedBox(width: 280, child: caseList),
                  const VerticalDivider(width: 1),
                  Expanded(child: workspace),
                ],
              );
            }

            return Column(
              children: [
                SizedBox(height: 148, child: caseList),
                const Divider(height: 1),
                Expanded(child: workspace),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showLinkSnackBar(String url) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Link tapped: $url')));
  }
}

class _CaseList extends StatelessWidget {
  const _CaseList({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _displayMarkdownCases.length + 1,
        scrollDirection: MediaQuery.sizeOf(context).width >= 980
            ? Axis.vertical
            : Axis.horizontal,
        itemBuilder: (BuildContext context, int index) {
          final bool allCases = index == 0;
          final int caseIndex = index - 1;
          final bool selected = allCases
              ? selectedIndex < 0
              : selectedIndex == caseIndex;
          final String title = allCases
              ? 'All cases'
              : _displayMarkdownCases[caseIndex].title;
          final String group = allCases
              ? '${_regularMarkdownCases.length} sections'
              : _displayMarkdownCases[caseIndex].group;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width >= 980 ? null : 220,
              child: Material(
                color: selected
                    ? colors.secondaryContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(caseIndex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Workspace extends StatefulWidget {
  const _Workspace({
    super.key,
    required this.nodes,
    required this.source,
    required this.result,
    required this.error,
    required this.loading,
    required this.renderPaused,
    required this.streamedCharacters,
    required this.totalCharacters,
    required this.showSource,
    required this.debugTokens,
    required this.tokenAnimationBuilder,
    required this.tokenAnimationName,
    required this.onLinkTap,
  });

  final List<MarkdownBlock> nodes;
  final String source;
  final MarkdownParseResult? result;
  final String? error;
  final bool loading;
  final bool renderPaused;
  final int streamedCharacters;
  final int totalCharacters;
  final bool showSource;
  final bool debugTokens;
  final StreamingMarkdownTokenAnimationBuilder tokenAnimationBuilder;
  final String tokenAnimationName;
  final ValueChanged<String> onLinkTap;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  final GlobalKey _previewKey = GlobalKey();
  final GlobalKey _sourceKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final bool split =
        widget.showSource && MediaQuery.sizeOf(context).width >= 760;
    final Widget preview = _PreviewPane(
      key: _previewKey,
      nodes: widget.nodes,
      result: widget.result,
      error: widget.error,
      loading: widget.loading,
      renderPaused: widget.renderPaused,
      streamedCharacters: widget.streamedCharacters,
      totalCharacters: widget.totalCharacters,
      debugTokens: widget.debugTokens,
      tokenAnimationBuilder: widget.tokenAnimationBuilder,
      tokenAnimationName: widget.tokenAnimationName,
      onLinkTap: widget.onLinkTap,
    );

    if (!widget.showSource) {
      return preview;
    }

    final Widget sourcePane = _SourcePane(
      key: _sourceKey,
      source: widget.source,
    );
    if (split) {
      return Row(
        children: [
          Expanded(flex: 3, child: preview),
          const VerticalDivider(width: 1),
          Expanded(flex: 2, child: sourcePane),
        ],
      );
    }

    return Column(
      children: [
        Expanded(flex: 3, child: preview),
        const Divider(height: 1),
        Expanded(flex: 2, child: sourcePane),
      ],
    );
  }
}

class _PreviewPane extends StatefulWidget {
  const _PreviewPane({
    super.key,
    required this.nodes,
    required this.result,
    required this.error,
    required this.loading,
    required this.renderPaused,
    required this.streamedCharacters,
    required this.totalCharacters,
    required this.debugTokens,
    required this.tokenAnimationBuilder,
    required this.tokenAnimationName,
    required this.onLinkTap,
  });

  final List<MarkdownBlock> nodes;
  final MarkdownParseResult? result;
  final String? error;
  final bool loading;
  final bool renderPaused;
  final int streamedCharacters;
  final int totalCharacters;
  final bool debugTokens;
  final StreamingMarkdownTokenAnimationBuilder tokenAnimationBuilder;
  final String tokenAnimationName;
  final ValueChanged<String> onLinkTap;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Column(
      children: [
        _ParserStatusBar(
          result: widget.result,
          loading: widget.loading,
          error: widget.error,
          renderPaused: widget.renderPaused,
          streamedCharacters: widget.streamedCharacters,
          totalCharacters: widget.totalCharacters,
          tokenAnimationName: widget.tokenAnimationName,
          tracingTokenMerge: widget.debugTokens,
        ),
        Expanded(
          child: widget.error == null
              ? _PreviewComparison(
                  nodes: widget.nodes,
                  loading: widget.loading,
                  renderPaused: widget.renderPaused,
                  streamedCharacters: widget.streamedCharacters,
                  debugTokens: widget.debugTokens,
                  tokenAnimationBuilder: widget.tokenAnimationBuilder,
                  onLinkTap: widget.onLinkTap,
                  markdownTheme: AnimatedMarkdownThemeData(
                    blockSpacing: 16,
                    quoteBackgroundColor: const Color(0x111F7A68),
                    codeBlockBackgroundColor: const Color(0xFF0F172A),
                    codeBlockHeaderBackgroundColor: const Color(0xFF1E293B),
                    metadataBackgroundColor: const Color(0xFFF8FAFC),
                    metadataBorderColor: const Color(0xFFCBD5E1),
                    metadataTextStyle: const TextStyle(
                      color: Color(0xFF334155),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    tableBorderColor: colors.outlineVariant,
                    tableHeaderBackgroundColor: Color.alphaBlend(
                      colors.onSurface.withValues(alpha: 0.06),
                      colors.surface,
                    ),
                    thematicBreakColor: const Color(0xFF94A3B8),
                    imageErrorBackgroundColor: const Color(0xFFE2E8F0),
                    imageErrorTextStyle: const TextStyle(
                      color: Color(0xFF334155),
                    ),
                    selectionColor: const Color(0x5538BDF8),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(widget.error!, textAlign: TextAlign.center),
                  ),
                ),
        ),
      ],
    );
  }
}

class _PreviewComparison extends StatefulWidget {
  const _PreviewComparison({
    required this.nodes,
    required this.loading,
    required this.renderPaused,
    required this.streamedCharacters,
    required this.debugTokens,
    required this.tokenAnimationBuilder,
    required this.onLinkTap,
    required this.markdownTheme,
  });

  final List<MarkdownBlock> nodes;
  final bool loading;
  final bool renderPaused;
  final int streamedCharacters;
  final bool debugTokens;
  final StreamingMarkdownTokenAnimationBuilder tokenAnimationBuilder;
  final ValueChanged<String> onLinkTap;
  final StreamingMarkdownThemeData markdownTheme;

  @override
  State<_PreviewComparison> createState() => _PreviewComparisonState();
}

class _PreviewComparisonState extends State<_PreviewComparison> {
  final GlobalKey _selectionOffKey = GlobalKey();
  final GlobalKey _selectionOnKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool sideBySide = constraints.maxWidth >= 560;
        final Widget selectionOff = _MarkdownPreviewSurface(
          key: _selectionOffKey,
          title: 'Selection off',
          nodes: widget.nodes,
          loading: widget.loading,
          renderPaused: widget.renderPaused,
          streamedCharacters: widget.streamedCharacters,
          enableSelection: false,
          debugTokens: widget.debugTokens,
          tokenAnimationBuilder: widget.tokenAnimationBuilder,
          onLinkTap: widget.onLinkTap,
          markdownTheme: widget.markdownTheme,
        );
        final Widget selectionOn = _MarkdownPreviewSurface(
          key: _selectionOnKey,
          title: 'Selection on',
          nodes: widget.nodes,
          loading: widget.loading,
          renderPaused: widget.renderPaused,
          streamedCharacters: widget.streamedCharacters,
          enableSelection: true,
          debugTokens: widget.debugTokens,
          tokenAnimationBuilder: widget.tokenAnimationBuilder,
          onLinkTap: widget.onLinkTap,
          markdownTheme: widget.markdownTheme,
        );

        if (sideBySide) {
          return Row(
            children: [
              Expanded(child: selectionOff),
              const VerticalDivider(width: 1),
              Expanded(child: selectionOn),
            ],
          );
        }

        return Column(
          children: [
            Expanded(child: selectionOff),
            const Divider(height: 1),
            Expanded(child: selectionOn),
          ],
        );
      },
    );
  }
}

class _MarkdownPreviewSurface extends StatefulWidget {
  const _MarkdownPreviewSurface({
    super.key,
    required this.title,
    required this.nodes,
    required this.loading,
    required this.renderPaused,
    required this.streamedCharacters,
    required this.enableSelection,
    required this.debugTokens,
    required this.tokenAnimationBuilder,
    required this.onLinkTap,
    required this.markdownTheme,
  });

  final String title;
  final List<MarkdownBlock> nodes;
  final bool loading;
  final bool renderPaused;
  final int streamedCharacters;
  final bool enableSelection;
  final bool debugTokens;
  final StreamingMarkdownTokenAnimationBuilder tokenAnimationBuilder;
  final ValueChanged<String> onLinkTap;
  final StreamingMarkdownThemeData markdownTheme;

  @override
  State<_MarkdownPreviewSurface> createState() =>
      _MarkdownPreviewSurfaceState();
}

class _MarkdownPreviewSurfaceState extends State<_MarkdownPreviewSurface> {
  static const Duration _tokenArrivalDelay = Duration(milliseconds: 350);
  static const Duration _tokenFadeInDuration = Duration(milliseconds: 1800);
  static const Duration _autoScrollInterval = Duration(milliseconds: 80);
  static const int _stableTicksBeforeStop = 12;

  final ScrollController _controller = ScrollController();
  Timer? _autoScrollTimer;
  double _lastMaxScrollExtent = -1;
  int _stableTicks = 0;
  DateTime _autoScrollUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _MarkdownPreviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamedCharacters != widget.streamedCharacters ||
        oldWidget.nodes.length != widget.nodes.length ||
        oldWidget.loading != widget.loading ||
        oldWidget.enableSelection != widget.enableSelection ||
        oldWidget.debugTokens != widget.debugTokens) {
      if (widget.streamedCharacters < oldWidget.streamedCharacters ||
          (oldWidget.nodes.isNotEmpty && widget.nodes.isEmpty)) {
        _stickToBottom = true;
      }
      _startAutoScroll(activeFor: _estimatedRenderActivityDuration());
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoScroll({Duration activeFor = const Duration(seconds: 2)}) {
    _stableTicks = 0;
    final DateTime until = DateTime.now().add(activeFor);
    if (until.isAfter(_autoScrollUntil)) {
      _autoScrollUntil = until;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRenderedEnd());
    _autoScrollTimer ??= Timer.periodic(
      _autoScrollInterval,
      (_) => _scrollToRenderedEnd(),
    );
  }

  void _scrollToRenderedEnd() {
    if (!mounted || !_controller.hasClients) {
      return;
    }

    final ScrollPosition position = _controller.position;
    final double maxExtent = position.maxScrollExtent;
    if (_stickToBottom && (maxExtent - position.pixels).abs() > 0.5) {
      _controller.jumpTo(maxExtent);
    }

    final bool renderActivityLikelyDone =
        !widget.loading && DateTime.now().isAfter(_autoScrollUntil);
    if (maxExtent == _lastMaxScrollExtent && renderActivityLikelyDone) {
      _stableTicks += 1;
    } else {
      _stableTicks = 0;
      _lastMaxScrollExtent = maxExtent;
    }

    if (_stableTicks >= _stableTicksBeforeStop) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
    }
  }

  bool _isNearBottom(ScrollMetrics metrics) {
    return metrics.maxScrollExtent - metrics.pixels <= 24;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _stickToBottom = false;
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        !_isNearBottom(notification.metrics)) {
      _stickToBottom = false;
      return false;
    }

    if (notification is ScrollEndNotification) {
      _stickToBottom = _isNearBottom(notification.metrics);
    }
    return false;
  }

  Duration _estimatedRenderActivityDuration() {
    if (widget.loading) {
      return const Duration(seconds: 3);
    }

    int tokenCount = 0;
    for (final MarkdownBlock node in widget.nodes) {
      final String text =
          (node.content.trim().isNotEmpty ? node.content : node.raw).trim();
      if (text.isEmpty) {
        continue;
      }
      tokenCount += RegExp(r'\S+').allMatches(text).length;
    }

    if (tokenCount <= 0) {
      return _tokenFadeInDuration;
    }
    return (_tokenArrivalDelay * tokenCount) + _tokenFadeInDuration;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: 36,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          color: widget.enableSelection
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: widget.enableSelection
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: SingleChildScrollView(
                  controller: _controller,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        width: double.infinity,
                        child: AnimatedStreamingMarkdown(
                          blocks: widget.nodes,
                          placeholder: '',
                          asSliver: false,
                          padding: const EdgeInsets.all(20),
                          enableSelection: widget.enableSelection,
                          tokenStaggerDelay: _tokenArrivalDelay,
                          tokenAnimationDuration: _tokenFadeInDuration,
                          tokenAnimationBuilder: widget.tokenAnimationBuilder,
                          tokenAnimationPaused: widget.renderPaused,
                          showTokenDebugColors: widget.debugTokens,
                          tokenCompaction: widget.debugTokens
                              ? AnimatedMarkdownTokenCompaction.always
                              : AnimatedMarkdownTokenCompaction.automatic,
                          allowIncompleteInlineSyntax: true,
                          onTokenDelay: () => _startAutoScroll(
                            activeFor:
                                _tokenFadeInDuration + _tokenArrivalDelay,
                          ),
                          onTokenAnimationEnd: () => _startAutoScroll(
                            activeFor: const Duration(milliseconds: 320),
                          ),
                          onLinkTap: widget.onLinkTap,
                          theme: widget.markdownTheme,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ParserStatusBar extends StatelessWidget {
  const _ParserStatusBar({
    required this.result,
    required this.loading,
    required this.renderPaused,
    required this.error,
    required this.streamedCharacters,
    required this.totalCharacters,
    required this.tokenAnimationName,
    required this.tracingTokenMerge,
  });

  final MarkdownParseResult? result;
  final bool loading;
  final bool renderPaused;
  final String? error;
  final int streamedCharacters;
  final int totalCharacters;
  final String tokenAnimationName;
  final bool tracingTokenMerge;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final MarkdownParseResult? currentResult = result;
    final bool hasProgress = totalCharacters > 0;
    final int progressPercent = hasProgress
        ? ((streamedCharacters / totalCharacters) * 100).clamp(0, 100).round()
        : 0;
    final String statusText = error != null
        ? 'Parser error'
        : renderPaused
        ? currentResult == null
              ? 'Paused'
              : 'Paused $progressPercent% - ${currentResult.mode} - '
                    '${currentResult.blocks.length} render nodes'
        : loading
        ? currentResult == null
              ? 'Streaming markdown'
              : 'Streaming $progressPercent% - ${currentResult.mode} - '
                    '${currentResult.blocks.length} render nodes'
        : currentResult == null
        ? 'Waiting'
        : '${currentResult.mode} - '
              '${currentResult.blocks.length} render nodes - '
              '${currentResult.totalTime.inMilliseconds} ms';

    return Container(
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      color: colors.surfaceContainerHighest,
      child: Row(
        children: [
          if (renderPaused)
            Icon(Icons.pause_circle_outline, size: 18, color: colors.primary)
          else if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              error == null ? Icons.check_circle_outline : Icons.error_outline,
              size: 18,
              color: error == null ? colors.primary : colors.error,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tracingTokenMerge
                ? '$tokenAnimationName - merge trace'
                : tokenAnimationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcePane extends StatefulWidget {
  const _SourcePane({super.key, required this.source});

  final String source;

  @override
  State<_SourcePane> createState() => _SourcePaneState();
}

class _SourcePaneState extends State<_SourcePane> {
  final ScrollController _sourceScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _SourcePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _scheduleAutoScroll();
    }
  }

  @override
  void dispose() {
    _sourceScrollController.dispose();
    super.dispose();
  }

  void _scheduleAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sourceScrollController.hasClients) {
        return;
      }
      _sourceScrollController.jumpTo(
        _sourceScrollController.position.maxScrollExtent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle codeStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.45,
        ) ??
        const TextStyle(fontFamily: 'monospace', height: 1.45);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        controller: _sourceScrollController,
        padding: const EdgeInsets.all(16),
        child: SelectableText(widget.source, style: codeStyle),
      ),
    );
  }
}

class _TokenAnimationPreset {
  const _TokenAnimationPreset({required this.name, required this.builder});

  final String name;
  final StreamingMarkdownTokenAnimationBuilder builder;
}

final List<_TokenAnimationPreset> _tokenAnimationPresets =
    <_TokenAnimationPreset>[
      _TokenAnimationPreset(
        name: 'Fade (default)',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          return Opacity(opacity: token.value, child: token.child);
        },
      ),
      _TokenAnimationPreset(
        name: 'Slide up',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = Curves.easeOutCubic.transform(token.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 10),
              child: token.child,
            ),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Slide right',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = Curves.easeOut.transform(token.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset((1 - t) * -14, 0),
              child: token.child,
            ),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Scale pop',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = Curves.easeOutBack.transform(token.value);
          return Transform.scale(
            scale: 0.84 + (0.16 * t),
            alignment: Alignment.bottomLeft,
            child: Opacity(opacity: token.value, child: token.child),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Rotate in',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = Curves.easeOutQuart.transform(token.value);
          return Transform.rotate(
            angle: (1 - t) * -0.16,
            alignment: Alignment.bottomLeft,
            child: Opacity(opacity: token.value, child: token.child),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Blur to clear',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = Curves.easeOut.transform(token.value);
          return ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: (1 - t) * 2.6,
              sigmaY: (1 - t) * 2.6,
            ),
            child: Opacity(opacity: t, child: token.child),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Wave wobble',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = token.value;
          final double wave = math.sin(t * math.pi * 3) * (1 - t) * 7;
          return Opacity(
            opacity: Curves.easeOut.transform(t),
            child: Transform.translate(
              offset: Offset(0, -wave),
              child: token.child,
            ),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Flip Y',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = Curves.easeOutCubic.transform(token.value);
          final Matrix4 matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY((1 - t) * -1.1);
          return Transform(
            alignment: Alignment.centerLeft,
            transform: matrix,
            child: Opacity(opacity: t, child: token.child),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Elastic pop',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = Curves.elasticOut.transform(token.value);
          return Transform.scale(
            scale: 0.7 + (0.3 * t),
            alignment: Alignment.bottomLeft,
            child: Opacity(opacity: token.value, child: token.child),
          );
        },
      ),
      _TokenAnimationPreset(
        name: 'Glitchy',
        builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
          final double t = token.value;
          final double shakeX = math.sin(t * math.pi * 22) * (1 - t) * 4.0;
          final double shakeY = math.cos(t * math.pi * 18) * (1 - t) * 2.0;
          return Opacity(
            opacity: Curves.easeOut.transform(t),
            child: Transform.translate(
              offset: Offset(shakeX, shakeY),
              child: Transform.scale(
                scale: 0.92 + (0.08 * Curves.easeOutBack.transform(t)),
                alignment: Alignment.bottomLeft,
                child: token.child,
              ),
            ),
          );
        },
      ),
    ];

class _MarkdownCase {
  const _MarkdownCase({
    required this.title,
    required this.group,
    required this.markdown,
  });

  final String title;
  final String group;
  final String markdown;
}

final List<_MarkdownCase> _regularMarkdownCases = <_MarkdownCase>[
  const _MarkdownCase(
    title: 'Front matter and separators',
    group: 'Metadata',
    markdown: r'''---
title: Streaming Markdown fixtures
tags:
  - parser
  - renderer
draft: false
---

# Front matter

Front matter is rendered as a metadata block when it appears at the top of the
document.

---

Thematic breaks render as horizontal dividers.

***

Underscore breaks are supported too.
''',
  ),
  const _MarkdownCase(
    title: 'Headings and paragraphs',
    group: 'Blocks',
    markdown: r'''# Heading level 1

## Heading level 2

### Heading level 3

#### Heading level 4

##### Heading level 5

###### Heading level 6

Setext heading level 1
======================

Setext heading level 2
----------------------

Paragraph text keeps normal Markdown prose readable while streaming. A newline
inside the same paragraph remains part of the rendered text.
''',
  ),
  const _MarkdownCase(
    title: 'Inline formatting',
    group: 'Inline',
    markdown: r'''# Inline formatting

This paragraph includes **bold**, __bold with underscores__, *italic*,
_italic with underscores_, ***bold italic***, ___bold italic underscores___,
~~strikethrough~~, and `inline code`.

Nested emphasis also works: **bold text with _italic inside_ and `code`**.

Unclosed delimiters can render during streaming: **bold while the chunk is still
arriving.
''',
  ),
  const _MarkdownCase(
    title: 'Links and references',
    group: 'Inline',
    markdown: r'''# Links and references

Inline links render as tappable spans: [OpenAI](https://openai.com).

Autolinks render from angle brackets: <https://github.com>.

Full reference links work with definitions: [Flutter docs][flutter].

Collapsed references use the label as the key: [Dart][].

Shortcut references work too: [pub.dev].

[flutter]: https://docs.flutter.dev
[dart]: https://dart.dev
[pub.dev]: https://pub.dev
''',
  ),
  const _MarkdownCase(
    title: 'Images',
    group: 'Media',
    markdown: r'''# Images

![Remote demo image](https://picsum.photos/seed/streaming-markdown/960/360)

Inline images inside a paragraph are represented inline:
before ![small marker](https://picsum.photos/seed/marker/120/120) after.
''',
  ),
  const _MarkdownCase(
    title: 'Lists and tasks',
    group: 'Blocks',
    markdown: r'''# Lists and tasks

- Unordered item
- Item with **inline formatting**
  - Nested unordered item
  - Another nested item
    - Third level item

1. Ordered item
2. Ordered item starting from the source number
   1. Nested ordered item
   2. Another nested ordered item

- [x] Completed task
- [ ] Open task
- [X] Uppercase completed task
''',
  ),
  const _MarkdownCase(
    title: 'Block quotes and callouts',
    group: 'Blocks',
    markdown: r'''# Block quotes and callouts

> A normal block quote keeps quoted prose visually separate.
> It can span more than one line.

> [!NOTE] Note
> Notes render with an info treatment.

> [!TIP] Tip
> Tips render with a success treatment.

> [!IMPORTANT] Important
> Important callouts have their own accent.

> [!WARNING] Warning
> Warnings render with a warning accent.

> [!CAUTION] Caution
> Caution callouts render with an error accent.
''',
  ),
  const _MarkdownCase(
    title: 'Code blocks',
    group: 'Blocks',
    markdown: r'''# Code blocks

```dart
class Greeter {
  const Greeter(this.name);

  final String name;

  String call() => 'Hello, $name';
}
```

~~~json
{
  "streaming": true,
  "blocks": ["paragraph", "code", "table"]
}
~~~

    final value = 'Indented code block';
    print(value);
''',
  ),
  const _MarkdownCase(
    title: 'Tables',
    group: 'GFM',
    markdown: r'''# Tables

| Case | Markdown | Rendered behavior |
| :--- | :------: | ---------------: |
| Inline code | `a | b` | Keeps pipe inside code |
| Escaped pipe | `a \| b` | Keeps escaped separator |
| Link | [docs](https://docs.flutter.dev) | Tappable cell content |

| Name | Status | Notes |
| --- | --- | --- |
| Alpha | Ready | Basic cells |
| Beta | Streaming | **Formatted** cell |
''',
  ),
  const _MarkdownCase(
    title: 'Footnotes',
    group: 'GFM',
    markdown: r'''# Footnotes

Streaming render can show footnote references inline.[^parser]

Multiple references can point at separate definitions.[^renderer]

[^parser]: The parser emits footnote definition nodes.
[^renderer]: The renderer displays definitions as compact rows.
''',
  ),
  const _MarkdownCase(
    title: 'HTML blocks',
    group: 'HTML',
    markdown: r'''<section>
  <h2>HTML block</h2>
  <p>HTML blocks render with Flutter widgets, including <strong>strong</strong>,
  <em>emphasis</em>, <code>inline code</code>, and
  <a href="https://dart.dev">links</a>.</p>
  <blockquote>Nested HTML block quotes are supported.</blockquote>
  <ul>
    <li>HTML unordered item</li>
    <li>Second unordered item</li>
  </ul>
  <ol>
    <li>HTML ordered item</li>
    <li>Second ordered item</li>
  </ol>
  <table>
    <thead>
      <tr><th>Column</th><th>Value</th></tr>
    </thead>
    <tbody>
      <tr><td>HTML table</td><td>Rendered</td></tr>
    </tbody>
  </table>
  <p>Line break<br>inside a paragraph.</p>
  <img src="https://picsum.photos/seed/html-block/700/240" alt="HTML image">
  <hr>
</section>
''',
  ),
];

final _MarkdownCase _stressMarkdownCase = _MarkdownCase(
  title: 'Stress test large markdown',
  group: 'Stress',
  markdown: _demoStressMarkdown,
);

final List<_MarkdownCase> _displayMarkdownCases = <_MarkdownCase>[
  ..._regularMarkdownCases,
  _stressMarkdownCase,
];

final String _demoStressMarkdown = _buildDemoStressMarkdown(
  sections: 80,
  paragraphRepeats: 3,
  listItemsPerSection: 5,
);

String _buildDemoStressMarkdown({
  required int sections,
  required int paragraphRepeats,
  required int listItemsPerSection,
}) {
  final StringBuffer out = StringBuffer()
    ..writeln('# Stress Test (Large Markdown)')
    ..writeln()
    ..writeln(
      'This case is intentionally heavy for render/parse benchmarking in the demo.',
    )
    ..writeln();

  for (int i = 1; i <= sections; i++) {
    out
      ..writeln('## Section $i')
      ..writeln();

    for (int p = 0; p < paragraphRepeats; p++) {
      out
        ..writeln(
          'Paragraph $p in section $i with **bold**, *italic*, '
          '[link](https://example.com/$i/$p), and `inline_code`.',
        )
        ..writeln();
    }

    out
      ..writeln('| Col A | Col B | Col C |')
      ..writeln('| --- | --- | --- |')
      ..writeln('| $i | ${i + 1} | ${i + 2} |')
      ..writeln('| ${i + 3} | ${i + 4} | ${i + 5} |')
      ..writeln();

    for (int l = 1; l <= listItemsPerSection; l++) {
      out.writeln('- [ ] task item $l in section $i');
    }
    out
      ..writeln()
      ..writeln('```dart')
      ..writeln('final section = $i;')
      ..writeln("print('stress section: \$section');")
      ..writeln('```')
      ..writeln();
  }

  return out.toString();
}

String get _allCasesMarkdown {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < _regularMarkdownCases.length; i++) {
    if (i > 0) {
      buffer
        ..writeln()
        ..writeln('---')
        ..writeln();
    }
    buffer.write(_regularMarkdownCases[i].markdown.trim());
    buffer.writeln();
  }
  return buffer.toString();
}
