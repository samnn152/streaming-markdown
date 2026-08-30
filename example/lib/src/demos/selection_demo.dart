import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';

import '../flutter_sdk_compat.dart';
import 'link_custom_demo.dart';

/// A small, deterministic selection playground used by the example app.
///
/// Keeping this fixture local makes the selection and rich-copy behavior
/// inspectable even when no chat provider or network connection is available.
class SelectionDemoPage extends StatefulWidget {
  const SelectionDemoPage({super.key});

  @override
  State<SelectionDemoPage> createState() => _SelectionDemoPageState();
}

class _SelectionDemoPageState extends State<SelectionDemoPage> {
  final AnimatedMarkdownSelectionController _selectionController =
      AnimatedMarkdownSelectionController();

  SelectionStrategy _strategy = SelectionStrategy.rich;

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  void _showCopyHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Select text, then use the platform copy action (⌘/Ctrl+C or the selection toolbar).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selection lab'),
        actions: [
          IconButton(
            key: const ValueKey<String>('open_link_custom_demo'),
            tooltip: 'Streaming link & custom widget',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LinkCustomDemoPage(),
                ),
              );
            },
            icon: const Icon(Icons.link_outlined),
          ),
          IconButton(
            key: const ValueKey<String>('selection_demo_clear'),
            tooltip: 'Clear selection',
            onPressed: _selectionController.clear,
            icon: const Icon(Icons.close_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 900;
            final Widget intro = _SelectionIntro(
              strategy: _strategy,
              controller: _selectionController,
              onStrategyChanged: (SelectionStrategy strategy) {
                setState(() => _strategy = strategy);
              },
              onCopyHint: _showCopyHint,
            );
            final Widget preview = _SelectionPreview(
              strategy: _strategy,
              controller: _selectionController,
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 330, child: intro),
                  VerticalDivider(width: 1, color: colors.outlineVariant),
                  Expanded(child: preview),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                intro,
                const SizedBox(height: 16),
                SizedBox(height: 560, child: preview),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SelectionIntro extends StatelessWidget {
  const _SelectionIntro({
    required this.strategy,
    required this.controller,
    required this.onStrategyChanged,
    required this.onCopyHint,
  });

  final SelectionStrategy strategy;
  final AnimatedMarkdownSelectionController controller;
  final ValueChanged<SelectionStrategy> onStrategyChanged;
  final VoidCallback onCopyHint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.primaryContainer,
                  colors.secondaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.ads_click_outlined, color: colors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Selection, made visible',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drag across real Markdown blocks and see one continuous selection, even through code, lists, links, and tables.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Copy strategy',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the payload produced when you copy the selected range.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SelectionStrategy>(
            key: const ValueKey<String>('selection_demo_strategy'),
            // ignore: deprecated_member_use
            value: strategy,
            decoration: const InputDecoration(
              labelText: 'Selection payload',
              prefixIcon: Icon(Icons.copy_all_outlined),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: SelectionStrategy.rich,
                child: Text('Rich HTML'),
              ),
              DropdownMenuItem(
                value: SelectionStrategy.raw,
                child: Text('Raw Markdown'),
              ),
              DropdownMenuItem(
                value: SelectionStrategy.plain,
                child: Text('Plain text'),
              ),
            ],
            onChanged: (SelectionStrategy? value) {
              if (value != null) {
                onStrategyChanged(value);
              }
            },
          ),
          const SizedBox(height: 12),
          _StrategyDescription(strategy: strategy),
          const SizedBox(height: 20),
          _SelectionStatus(
            controller: controller,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('selection_demo_select_all'),
                  onPressed: controller.selectAll,
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select all'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey<String>('selection_demo_copy_hint'),
                tooltip: 'How to copy',
                onPressed: onCopyHint,
                icon: const Icon(Icons.content_copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Tip: on desktop press ⌘/Ctrl+C. On mobile, long-press or use the native selection toolbar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SelectionStatus extends StatefulWidget {
  const _SelectionStatus({required this.controller});

  final AnimatedMarkdownSelectionController controller;

  @override
  State<_SelectionStatus> createState() => _SelectionStatusState();
}

class _SelectionStatusState extends State<_SelectionStatus> {
  late AnimatedMarkdownSelectionValue _value = widget.controller.value;
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_queueRefresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_queueRefresh);
    super.dispose();
  }

  void _queueRefresh() {
    if (_refreshQueued) {
      return;
    }
    _refreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshQueued = false;
      if (!mounted) {
        return;
      }
      setState(() => _value = widget.controller.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String excerpt =
        _value.selectedMarkdown.replaceAll(RegExp(r'\s+'), ' ').trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: flutterSurfaceContainerHighest(colors),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _value.hasSelection
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: _value.hasSelection
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _value.hasSelection
                        ? 'Selection is ready to copy'
                        : 'Nothing selected yet',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (_value.hasSelection) ...[
              const SizedBox(height: 8),
              Text(
                '${_value.selectedMarkdown.characters.length} characters selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (excerpt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StrategyDescription extends StatelessWidget {
  const _StrategyDescription({required this.strategy});

  final SelectionStrategy strategy;

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String text}) details = switch (strategy) {
      SelectionStrategy.rich => (
          icon: Icons.auto_awesome_outlined,
          text:
              'Preserves Markdown styling as HTML where the platform supports rich clipboard data.',
        ),
      SelectionStrategy.raw => (
          icon: Icons.code_outlined,
          text:
              'Keeps the source syntax, useful when moving a snippet back into a Markdown editor.',
        ),
      SelectionStrategy.plain => (
          icon: Icons.notes_outlined,
          text: 'Copies the rendered reading text without Markdown markers.',
        ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(details.icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(details.text)),
      ],
    );
  }
}

class _SelectionPreview extends StatelessWidget {
  const _SelectionPreview({
    required this.strategy,
    required this.controller,
  });

  final SelectionStrategy strategy;
  final AnimatedMarkdownSelectionController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey<String>('selection_demo_preview_card'),
      margin: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: flutterSurfaceContainerHighest(colors),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  Icon(Icons.article_outlined, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Markdown fixture',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Drag through spaces and past the final period below',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Chip(
                    avatar: Icon(Icons.touch_app_outlined, size: 16),
                    label: Text('Drag text'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedStreamingMarkdown.fromMarkdown(
                key: const ValueKey<String>('selection_demo_markdown'),
                markdown: _selectionFixture,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                enableSelection: true,
                selectionStrategy: strategy,
                selectionController: controller,
                showCodeBlockCopyButton: true,
                theme: AnimatedMarkdownThemeData(
                  blockSpacing: 16,
                  paragraphTextStyle: const TextStyle(
                    fontSize: 18,
                    height: 1.5,
                  ),
                  selectionColor: colors.primary.withAlpha(88),
                  codeBlockBackgroundColor: const Color(0xFF0F172A),
                  codeBlockHeaderBackgroundColor: const Color(0xFF1E293B),
                  codeBlockTextStyle: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                  ),
                  inlineCodeBackgroundColor: colors.primaryContainer,
                  inlineCodeTextStyle: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontFamily: 'monospace',
                    fontSize: 18,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const String _selectionFixture = '''# One selection, many Markdown blocks

Select across **bold text**, *italics*, [a link](https://pub.dev), and `inline code`.

The renderer keeps the selection anchored while the document contains different visual treatments.

- Lists stay part of the same document selection
- Code keeps its readable monospace presentation
- Tables remain horizontally scrollable when needed

| Feature | Rich copy |
| --- | --- |
| Formatting | HTML + plain fallback |
| Source | Stable Markdown offsets |
| Platforms | Web, mobile, desktop |

```dart
final selection = controller.value.selection;
print('Selected source: \${selection.start}..\${selection.end}');
```

Try **Select all**, then copy using the native toolbar or ⌘/Ctrl+C.''';
