import 'dart:async';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';

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

  final StreamingMarkdownParseWorker _worker = StreamingMarkdownParseWorker();

  List<MarkdownRenderNode> _nodes = const <MarkdownRenderNode>[];
  StreamingMarkdownParseResult? _result;
  int _selectedCase = -1;
  bool _workerStarted = false;
  bool _loading = true;
  bool _showSource = true;
  bool _selectionEnabled = true;
  bool _debugTokens = false;
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
      _error = null;
      _streamedCharacters = streamMarkdown ? 0 : markdown.length;
      _totalCharacters = markdown.length;
      if (streamMarkdown) {
        _nodes = const <MarkdownRenderNode>[];
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
          final StreamingMarkdownParseResult result = await _requestParse(
            'append',
            chunk,
          );
          if (!mounted || generation != _renderGeneration) {
            return;
          }
          setState(() {
            _nodes = result.renderNodes;
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

      final StreamingMarkdownParseResult result = await _requestParse(
        'set',
        markdown,
      );
      if (!mounted || generation != _renderGeneration) {
        return;
      }
      setState(() {
        _nodes = result.renderNodes;
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

  Future<StreamingMarkdownParseResult> _requestParse(String op, String text) {
    return _worker.request(op: op, text: text, includeNodes: true);
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
    return _markdownCases[_selectedCase].markdown;
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
    return _markdownCases[_selectedCase].title;
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

  void _toggleSelection() {
    setState(() {
      _selectionEnabled = !_selectionEnabled;
    });
  }

  void _toggleDebugTokens() {
    setState(() {
      _debugTokens = !_debugTokens;
    });
    unawaited(_renderActiveMarkdown());
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
            tooltip: _showSource ? 'Hide source' : 'Show source',
            icon: Icon(
              _showSource
                  ? Icons.vertical_split_outlined
                  : Icons.article_outlined,
            ),
            onPressed: _toggleSource,
          ),
          IconButton(
            tooltip: _selectionEnabled
                ? 'Disable text selection'
                : 'Enable text selection',
            icon: Icon(
              _selectionEnabled
                  ? Icons.text_fields_outlined
                  : Icons.text_format_outlined,
            ),
            onPressed: _toggleSelection,
          ),
          IconButton(
            tooltip: _debugTokens ? 'Disable token colors' : 'Show tokens',
            icon: Icon(
              _debugTokens
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: _toggleDebugTokens,
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
              nodes: _nodes,
              source: _visibleMarkdown,
              result: _result,
              error: _error,
              loading: _loading,
              streamedCharacters: _streamedCharacters,
              totalCharacters: _totalCharacters,
              showSource: _showSource,
              enableSelection: _selectionEnabled,
              debugTokens: _debugTokens,
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
        itemCount: _markdownCases.length + 1,
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
              : _markdownCases[caseIndex].title;
          final String group = allCases
              ? '${_markdownCases.length} sections'
              : _markdownCases[caseIndex].group;

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

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.nodes,
    required this.source,
    required this.result,
    required this.error,
    required this.loading,
    required this.streamedCharacters,
    required this.totalCharacters,
    required this.showSource,
    required this.enableSelection,
    required this.debugTokens,
    required this.onLinkTap,
  });

  final List<MarkdownRenderNode> nodes;
  final String source;
  final StreamingMarkdownParseResult? result;
  final String? error;
  final bool loading;
  final int streamedCharacters;
  final int totalCharacters;
  final bool showSource;
  final bool enableSelection;
  final bool debugTokens;
  final ValueChanged<String> onLinkTap;

  @override
  Widget build(BuildContext context) {
    final bool split = showSource && MediaQuery.sizeOf(context).width >= 760;
    final Widget preview = _PreviewPane(
      nodes: nodes,
      result: result,
      error: error,
      loading: loading,
      streamedCharacters: streamedCharacters,
      totalCharacters: totalCharacters,
      enableSelection: enableSelection,
      debugTokens: debugTokens,
      onLinkTap: onLinkTap,
    );

    if (!showSource) {
      return preview;
    }

    final Widget sourcePane = _SourcePane(source: source);
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
    required this.nodes,
    required this.result,
    required this.error,
    required this.loading,
    required this.streamedCharacters,
    required this.totalCharacters,
    required this.enableSelection,
    required this.debugTokens,
    required this.onLinkTap,
  });

  final List<MarkdownRenderNode> nodes;
  final StreamingMarkdownParseResult? result;
  final String? error;
  final bool loading;
  final int streamedCharacters;
  final int totalCharacters;
  final bool enableSelection;
  final bool debugTokens;
  final ValueChanged<String> onLinkTap;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane> {
  final ScrollController _previewScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _PreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamedCharacters != widget.streamedCharacters ||
        oldWidget.nodes.length != widget.nodes.length ||
        oldWidget.loading != widget.loading) {
      _scheduleAutoScroll();
    }
  }

  @override
  void dispose() {
    _previewScrollController.dispose();
    super.dispose();
  }

  void _scheduleAutoScroll() {
    if (!widget.loading) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_previewScrollController.hasClients) {
        return;
      }
      _previewScrollController.jumpTo(
        _previewScrollController.position.maxScrollExtent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ParserStatusBar(
          result: widget.result,
          loading: widget.loading,
          error: widget.error,
          streamedCharacters: widget.streamedCharacters,
          totalCharacters: widget.totalCharacters,
        ),
        Expanded(
          child: widget.error == null
              ? PrimaryScrollController(
                  controller: _previewScrollController,
                  automaticallyInheritForPlatforms: TargetPlatform.values
                      .toSet(),
                  child: StreamingMarkdownRenderView(
                    nodes: widget.nodes,
                    emptyPlaceholder: '',
                    padding: const EdgeInsets.all(20),
                    enableTextSelection: widget.enableSelection,
                    tokenArrivalDelay: const Duration(milliseconds: 35),
                    tokenFadeInDuration: const Duration(milliseconds: 180),
                    debugTokenHighlight: widget.debugTokens,
                    allowUnclosedInlineDelimiters: true,
                    onLinkTap: widget.onLinkTap,
                    markdownTheme: const StreamingMarkdownThemeData(
                      blockSpacing: 16,
                      quoteBackgroundColor: Color(0x111F7A68),
                      codeBlockBackgroundColor: Color(0xFF0F172A),
                      codeBlockHeaderBackgroundColor: Color(0xFF1E293B),
                      metadataBackgroundColor: Color(0xFFF8FAFC),
                      metadataBorderColor: Color(0xFFCBD5E1),
                      metadataTextStyle: TextStyle(
                        color: Color(0xFF334155),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      tableBorderColor: Color(0xFFCBD5E1),
                      tableHeaderBackgroundColor: Color(0xFFE2E8F0),
                      thematicBreakColor: Color(0xFF94A3B8),
                      imageErrorBackgroundColor: Color(0xFFE2E8F0),
                      imageErrorTextStyle: TextStyle(color: Color(0xFF334155)),
                      selectionColor: Color(0x5538BDF8),
                    ),
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

class _ParserStatusBar extends StatelessWidget {
  const _ParserStatusBar({
    required this.result,
    required this.loading,
    required this.error,
    required this.streamedCharacters,
    required this.totalCharacters,
  });

  final StreamingMarkdownParseResult? result;
  final bool loading;
  final String? error;
  final int streamedCharacters;
  final int totalCharacters;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final StreamingMarkdownParseResult? currentResult = result;
    final bool hasProgress = totalCharacters > 0;
    final int progressPercent = hasProgress
        ? ((streamedCharacters / totalCharacters) * 100).clamp(0, 100).round()
        : 0;
    final String statusText = error != null
        ? 'Parser error'
        : loading
        ? currentResult == null
              ? 'Streaming markdown'
              : 'Streaming $progressPercent% - ${currentResult.mode} - '
                    '${currentResult.renderNodes.length} render nodes'
        : currentResult == null
        ? 'Waiting'
        : '${currentResult.mode} - '
              '${currentResult.renderNodes.length} render nodes - '
              '${currentResult.totalTime.inMilliseconds} ms';

    return Container(
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      color: colors.surfaceContainerHighest,
      child: Row(
        children: [
          if (loading)
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
        ],
      ),
    );
  }
}

class _SourcePane extends StatefulWidget {
  const _SourcePane({required this.source});

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

final List<_MarkdownCase> _markdownCases = <_MarkdownCase>[
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

String get _allCasesMarkdown {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < _markdownCases.length; i++) {
    if (i > 0) {
      buffer
        ..writeln()
        ..writeln('---')
        ..writeln();
    }
    buffer.write(_markdownCases[i].markdown.trim());
    buffer.writeln();
  }
  return buffer.toString();
}
