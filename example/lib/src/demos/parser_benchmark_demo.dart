import 'dart:async';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ParserBenchmarkDemoApp());
}

class ParserBenchmarkDemoApp extends StatelessWidget {
  const ParserBenchmarkDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parser Benchmark Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF265D73),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF265D73),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ParserBenchmarkDemoPage(),
    );
  }
}

class ParserBenchmarkDemoPage extends StatefulWidget {
  const ParserBenchmarkDemoPage({super.key});

  @override
  State<ParserBenchmarkDemoPage> createState() =>
      _ParserBenchmarkDemoPageState();
}

class _ParserBenchmarkDemoPageState extends State<ParserBenchmarkDemoPage> {
  static const List<int> _sectionOptions = <int>[1, 5, 20, 80];
  static const List<int> _iterationOptions = <int>[1, 10, 50, 200];

  int _sections = 1;
  int _iterations = 10;
  bool _running = false;
  bool _warming = false;
  String? _error;
  String? _warmUpLine;
  List<_ParserBenchmarkResult> _results = const <_ParserBenchmarkResult>[];

  String get _markdown => _buildMarkdown(_sections);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_run());
      }
    });
  }

  Future<void> _warmUp() async {
    setState(() {
      _warming = true;
      _error = null;
    });
    try {
      final StreamingMarkdownWarmUpResult result =
          await warmUpStreamingMarkdownParser(includeWorker: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _warmUpLine =
            'native=${result.nativeAvailable} current=${_ms(result.currentIsolateTime)} worker=${_ms(result.workerTime)} total=${_ms(result.totalTime)}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _warming = false;
        });
      }
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _results = const <_ParserBenchmarkResult>[];
    });

    try {
      final String markdown = _markdown;
      final List<_ParserBenchmarkResult> results = <_ParserBenchmarkResult>[
        _runPureDart(markdown, _iterations),
        _runSyncNative(markdown, _iterations),
        await _runIsolateWorker(markdown, _iterations),
      ];
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  _ParserBenchmarkResult _runPureDart(String markdown, int iterations) {
    final MarkdownSyncParser parser = MarkdownSyncParser(
      backend: MarkdownSyncParserBackend.dart,
    );
    final List<Duration> times = <Duration>[];
    List<MarkdownBlock> blocks = const <MarkdownBlock>[];
    int blockCount = 0;
    try {
      for (int i = 0; i < iterations; i++) {
        final Stopwatch watch = Stopwatch()..start();
        final MarkdownParseResult result = parser.replace(markdown);
        watch.stop();
        blocks = result.blocks;
        blockCount = result.blocks.length;
        times.add(watch.elapsed);
      }
    } finally {
      parser.dispose();
    }
    return _ParserBenchmarkResult(
      name: 'Pure Dart',
      mode: 'sync-dart-set',
      blockCount: blockCount,
      nodesIncluded: true,
      blocks: blocks,
      times: times,
    );
  }

  _ParserBenchmarkResult _runSyncNative(String markdown, int iterations) {
    final MarkdownSyncParser parser = MarkdownSyncParser(
      backend: MarkdownSyncParserBackend.native,
    );
    final List<Duration> times = <Duration>[];
    String mode = '-';
    int blockCount = 0;
    bool nodesIncluded = false;
    List<MarkdownBlock> blocks = const <MarkdownBlock>[];
    try {
      for (int i = 0; i < iterations; i++) {
        final Stopwatch watch = Stopwatch()..start();
        final MarkdownParseResult result = parser.replace(markdown);
        watch.stop();
        mode = result.mode;
        blockCount = result.blocks.length;
        nodesIncluded = result.includesNodes;
        blocks = result.blocks;
        times.add(watch.elapsed);
      }
    } finally {
      parser.dispose();
    }
    return _ParserBenchmarkResult(
      name: 'Sync worker',
      mode: mode,
      blockCount: blockCount,
      nodesIncluded: nodesIncluded,
      blocks: blocks,
      times: times,
    );
  }

  Future<_ParserBenchmarkResult> _runIsolateWorker(
    String markdown,
    int iterations,
  ) async {
    final MarkdownStreamParser worker = MarkdownStreamParser();
    final List<Duration> times = <Duration>[];
    String mode = '-';
    int blockCount = 0;
    bool nodesIncluded = false;
    List<MarkdownBlock> blocks = const <MarkdownBlock>[];
    await worker.start();
    try {
      for (int i = 0; i < iterations; i++) {
        final Stopwatch watch = Stopwatch()..start();
        final MarkdownParseResult result = await worker.replace(markdown);
        watch.stop();
        mode = result.mode;
        blockCount = result.blocks.length;
        nodesIncluded = result.includesNodes;
        blocks = result.blocks;
        times.add(watch.elapsed);
      }
    } finally {
      worker.dispose();
    }
    return _ParserBenchmarkResult(
      name: 'Isolate worker',
      mode: mode,
      blockCount: blockCount,
      nodesIncluded: nodesIncluded,
      blocks: blocks,
      times: times,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String markdown = _markdown;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parser Benchmark'),
        actions: [
          IconButton(
            tooltip: 'Warm up',
            onPressed: _running || _warming ? null : _warmUp,
            icon: _warming
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.local_fire_department_outlined),
          ),
          IconButton(
            tooltip: 'Run',
            onPressed: _running || _warming ? null : _run,
            icon: _running
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: colors.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Dropdown<int>(
                      label: 'Sections',
                      value: _sections,
                      values: _sectionOptions,
                      onChanged: _running
                          ? null
                          : (int value) {
                              setState(() {
                                _sections = value;
                              });
                              unawaited(_run());
                            },
                    ),
                    _Dropdown<int>(
                      label: 'Iterations',
                      value: _iterations,
                      values: _iterationOptions,
                      onChanged: _running
                          ? null
                          : (int value) {
                              setState(() {
                                _iterations = value;
                              });
                              unawaited(_run());
                            },
                    ),
                    _MetricChip(
                      icon: Icons.notes_outlined,
                      label: '${markdown.length} chars',
                    ),
                    _MetricChip(
                      icon: Icons.format_list_bulleted_outlined,
                      label:
                          '${RegExp(r'\S+').allMatches(markdown).length} words',
                    ),
                  ],
                ),
              ),
            ),
            if (_warmUpLine != null)
              _StatusLine(
                icon: Icons.local_fire_department,
                text: _warmUpLine!,
              ),
            if (_error != null)
              _StatusLine(icon: Icons.error_outline, text: _error!),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget results = _ResultsPane(
                    results: _results,
                    running: _running,
                  );
                  if (constraints.maxWidth >= 860) {
                    return Column(
                      children: [
                        Expanded(child: results),
                        const Divider(height: 1),
                        SizedBox(
                          height: 180,
                          child: _SourcePane(markdown: markdown),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: results),
                      const Divider(height: 1),
                      SizedBox(
                        height: 180,
                        child: _SourcePane(markdown: markdown),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final T value in values)
            DropdownMenuItem<T>(value: value, child: Text('$value')),
        ],
        onChanged: onChanged == null
            ? null
            : (T? value) {
                if (value != null) {
                  onChanged!(value);
                }
              },
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, maxLines: 2)),
          ],
        ),
      ),
    );
  }
}

class _ResultsPane extends StatelessWidget {
  const _ResultsPane({required this.results, required this.running});

  final List<_ParserBenchmarkResult> results;
  final bool running;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: running
            ? const CircularProgressIndicator()
            : const Icon(Icons.speed_outlined, size: 56),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 860) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < results.length; i++) ...[
                Expanded(
                  child: _ResultTile(result: results[i], fillHeight: true),
                ),
                if (i < results.length - 1) const VerticalDivider(width: 1),
              ],
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int index) {
            return _ResultTile(result: results[index]);
          },
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, this.fillHeight = false});

  final _ParserBenchmarkResult result;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Widget preview = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AnimatedStreamingMarkdown(
          blocks: result.blocks,
          placeholder: '',
          padding: EdgeInsets.zero,
          tokenStaggerDelay: Duration.zero,
          tokenAnimationDuration: Duration.zero,
          tokenCompaction: AnimatedMarkdownTokenCompaction.disabled,
        ),
      ),
    );

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                result.name,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(result.mode, style: textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricChip(
              icon: Icons.functions_outlined,
              label: 'avg ${_ms(result.average)}',
            ),
            _MetricChip(
              icon: Icons.arrow_downward_outlined,
              label: 'min ${_ms(result.min)}',
            ),
            _MetricChip(
              icon: Icons.arrow_upward_outlined,
              label: 'max ${_ms(result.max)}',
            ),
            _MetricChip(
              icon: Icons.view_agenda_outlined,
              label: '${result.blockCount} blocks',
            ),
            _MetricChip(
              icon: Icons.data_object_outlined,
              label: result.nodesIncluded ? 'nodes' : 'stats',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BlockContentList(blocks: result.blocks),
        const SizedBox(height: 12),
        SizedBox(height: fillHeight ? 320 : 360, child: preview),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: fillHeight ? SingleChildScrollView(child: body) : body,
    );
  }
}

class _BlockContentList extends StatelessWidget {
  const _BlockContentList({required this.blocks});

  final List<MarkdownBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nodes',
          style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 240,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: blocks.length,
              separatorBuilder: (_, _) => const Divider(height: 14),
              itemBuilder: (BuildContext context, int index) {
                final MarkdownBlock block = blocks[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}. ${block.type}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _NodeTextLine(
                      label: 'content',
                      value: _compactNodeText(block.content),
                    ),
                    const SizedBox(height: 2),
                    _NodeTextLine(
                      label: 'raw',
                      value: _compactNodeText(block.raw),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeTextLine extends StatelessWidget {
  const _NodeTextLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: colors.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value.isEmpty ? '(empty)' : value),
        ],
      ),
    );
  }
}

String _compactNodeText(String value) {
  return value.replaceAll('\r', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _SourcePane extends StatelessWidget {
  const _SourcePane({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          markdown,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _ParserBenchmarkResult {
  const _ParserBenchmarkResult({
    required this.name,
    required this.mode,
    required this.blockCount,
    required this.nodesIncluded,
    required this.blocks,
    required this.times,
  });

  final String name;
  final String mode;
  final int blockCount;
  final bool nodesIncluded;
  final List<MarkdownBlock> blocks;
  final List<Duration> times;

  Duration get average {
    final int total = times.fold<int>(
      0,
      (int total, Duration duration) => total + duration.inMicroseconds,
    );
    return Duration(microseconds: total ~/ times.length);
  }

  Duration get min {
    return times.reduce((Duration a, Duration b) => a < b ? a : b);
  }

  Duration get max {
    return times.reduce((Duration a, Duration b) => a > b ? a : b);
  }
}

String _buildMarkdown(int sections) {
  final StringBuffer buffer = StringBuffer();
  for (int i = 1; i <= sections; i++) {
    buffer
      ..writeln('# GFM parser case $i')
      ..writeln()
      ..writeln(
        'Streaming markdown case $i mixes **strong**, _emphasis_, '
        '~~deleted text~~, `inline | code`, an autolink https://example.com/$i, '
        'and a reference link to [the docs][docs].',
      )
      ..writeln()
      ..writeln('> GFM quote content keeps **inline markdown** intact.')
      ..writeln()
      ..writeln('- [x] completed task for case $i')
      ..writeln('- [ ] pending task with `inline | pipe`')
      ..writeln('- nested content continues after the task marker')
      ..writeln()
      ..writeln('| Feature | Value | Notes |')
      ..writeln('| --- | ---: | --- |')
      ..writeln('| Case | $i | table row |')
      ..writeln('| Pipes | `a | b` | inline code cell |')
      ..writeln()
      ..writeln('Footnote reference[^case-$i] before the code fence.')
      ..writeln()
      ..writeln('```dart')
      ..writeln('final value$i = ${i * 17};')
      ..writeln("debugPrint('case $i: \$value$i');")
      ..writeln('```')
      ..writeln()
      ..writeln('[^case-$i]: Footnote body for parser case $i.')
      ..writeln();
  }
  buffer.writeln(
    '[docs]: https://pub.dev/packages/animated_streaming_markdown',
  );
  return buffer.toString();
}

String _ms(Duration? duration) {
  if (duration == null) {
    return '-';
  }
  final double value = duration.inMicroseconds / 1000;
  if (value >= 100) {
    return '${value.toStringAsFixed(1)} ms';
  }
  return '${value.toStringAsFixed(3)} ms';
}
