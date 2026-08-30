import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';

import '../flutter_sdk_compat.dart';

enum _IncompleteLinkPolicy { destination, label, hidden }

class LinkCustomDemoPage extends StatefulWidget {
  const LinkCustomDemoPage({super.key});

  @override
  State<LinkCustomDemoPage> createState() => _LinkCustomDemoPageState();
}

class _LinkCustomDemoPageState extends State<LinkCustomDemoPage> {
  final TextEditingController _sourceController =
      TextEditingController(text: '[Hel');
  final AnimatedMarkdownSelectionController _customSelectionController =
      AnimatedMarkdownSelectionController();

  _IncompleteLinkPolicy _policy = _IncompleteLinkPolicy.destination;
  String _source = '[Hel';
  String? _lastTappedDestination;
  bool _customObjectEnabled = true;

  @override
  void dispose() {
    _sourceController.dispose();
    _customSelectionController.dispose();
    super.dispose();
  }

  void _setSource(String source) {
    _sourceController.value = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );
    setState(() {
      _source = source;
      _lastTappedDestination = null;
    });
  }

  String _projectIncompleteLink(MarkdownInlineLink link) {
    return switch (_policy) {
      _IncompleteLinkPolicy.destination => link.destination,
      _IncompleteLinkPolicy.label => link.label,
      _IncompleteLinkPolicy.hidden => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final MarkdownParseResult parsed = MarkdownSyncParser.parseMarkdown(
      _source,
      backend: MarkdownSyncParserBackend.dart,
    );
    final MarkdownInlineLink? semanticLink =
        parsed.blocks.isEmpty || parsed.blocks.first.inlineLinks.isEmpty
            ? null
            : parsed.blocks.first.inlineLinks.first;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Streaming link & custom widget')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Incomplete link playground',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Change the source one character at a time, inspect its semantic state, then click the temporary destination.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ActionChip(
                key: const ValueKey<String>('link_demo_label_prefix'),
                label: const Text('[Hel'),
                onPressed: () => _setSource('[Hel'),
              ),
              ActionChip(
                key: const ValueKey<String>('link_demo_destination_prefix'),
                label: const Text('Destination arriving'),
                onPressed: () => _setSource('[Hello](https://hello'),
              ),
              ActionChip(
                key: const ValueKey<String>('link_demo_completed'),
                label: const Text('Completed link'),
                onPressed: () => _setSource('[Hello](https://hello)'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey<String>('link_demo_source'),
            controller: _sourceController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Streaming Markdown prefix',
              prefixIcon: Icon(Icons.stream_outlined),
            ),
            onChanged: (String value) => setState(() {
              _source = value;
              _lastTappedDestination = null;
            }),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_IncompleteLinkPolicy>(
            key: const ValueKey<String>('link_demo_policy'),
            segments: const <ButtonSegment<_IncompleteLinkPolicy>>[
              ButtonSegment<_IncompleteLinkPolicy>(
                value: _IncompleteLinkPolicy.destination,
                label: Text('Destination'),
              ),
              ButtonSegment<_IncompleteLinkPolicy>(
                value: _IncompleteLinkPolicy.label,
                label: Text('Label'),
              ),
              ButtonSegment<_IncompleteLinkPolicy>(
                value: _IncompleteLinkPolicy.hidden,
                label: Text('Hidden'),
              ),
            ],
            selected: <_IncompleteLinkPolicy>{_policy},
            onSelectionChanged: (Set<_IncompleteLinkPolicy> value) {
              setState(() => _policy = value.first);
            },
          ),
          const SizedBox(height: 16),
          Card(
            color: flutterSurfaceContainerHighest(colors),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Rendered output',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  AnimatedStreamingMarkdown(
                    key: ValueKey<String>('link-demo:$_source:$_policy'),
                    blocks: parsed.blocks,
                    padding: EdgeInsets.zero,
                    incompleteLinkTextBuilder: _projectIncompleteLink,
                    onLinkTap: (String destination) {
                      setState(() => _lastTappedDestination = destination);
                    },
                  ),
                  if (_lastTappedDestination != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      'Clicked: $_lastTappedDestination',
                      key: const ValueKey<String>('link_demo_clicked'),
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SemanticLinkInspector(link: semanticLink),
          const SizedBox(height: 28),
          Text(
            'Selectable custom object',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'The card below replaces the entire Markdown block. Its title '
            'supports character-level selection while the switch remains '
            'interactive.',
          ),
          const SizedBox(height: 12),
          AnimatedStreamingMarkdown.fromMarkdown(
            key: const ValueKey<String>('custom_widget_markdown'),
            markdown: 'Interactive custom widget',
            enableSelection: true,
            selectionController: _customSelectionController,
            padding: EdgeInsets.zero,
            blockBuilder: (
              BuildContext context,
              AnimatedMarkdownBlockContext block,
            ) {
              return AnimatedMarkdownSelectable.fragments(
                plainText: block.block.content,
                child: Card(
                  key: const ValueKey<String>('selectable_custom_widget'),
                  color: colors.primaryContainer,
                  child: SwitchListTile(
                    title: AnimatedMarkdownSelectionFragment(
                      plainText: block.block.content,
                      plainTextStart: 0,
                      child: Text(block.block.content),
                    ),
                    subtitle: const Text(
                      'Drag through part of the title or press “Select custom '
                      'object”.',
                    ),
                    value: _customObjectEnabled,
                    onChanged: (bool value) {
                      setState(() => _customObjectEnabled = value);
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              FilledButton.icon(
                key: const ValueKey<String>('custom_widget_select_all'),
                onPressed: _customSelectionController.selectAll,
                icon: const Icon(Icons.select_all),
                label: const Text('Select custom object'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: _customSelectionController,
                  builder: (BuildContext context, Widget? child) {
                    final String selected =
                        _customSelectionController.value.selectedMarkdown;
                    return Text(
                      selected.isEmpty
                          ? 'Nothing selected'
                          : 'Source: $selected',
                      key: const ValueKey<String>('custom_widget_selection'),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SemanticLinkInspector extends StatelessWidget {
  const _SemanticLinkInspector({required this.link});

  final MarkdownInlineLink? link;

  @override
  Widget build(BuildContext context) {
    final MarkdownInlineLink? value = link;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: value == null
            ? const Text('No inline-link semantic state')
            : Wrap(
                key: const ValueKey<String>('link_demo_semantics'),
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Chip(label: Text('label: ${value.label}')),
                  Chip(label: Text('destination: ${value.destination}')),
                  Chip(label: Text('completed: ${value.isCompleted}')),
                ],
              ),
      ),
    );
  }
}
