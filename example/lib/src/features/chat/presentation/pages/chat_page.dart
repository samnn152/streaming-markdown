import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/scheduler.dart';

import '../../../../flutter_sdk_compat.dart';
import '../../../../demos/selection_demo.dart';
import '../../../../demos/link_custom_demo.dart';
import '../../domain/models/chat_connection_settings.dart';
import '../bloc/chat_bloc.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.initialSettings,
    this.markdownTheme = const AnimatedMarkdownThemeData(),
    super.key,
  });

  final ChatConnectionSettings initialSettings;
  final AnimatedMarkdownThemeData markdownTheme;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const int _defaultTokenAnimationPresetIndex = 0;

  final GlobalKey _chatSurfaceKey = GlobalKey();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _systemPromptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late ChatConnectionSettings _settings = widget.initialSettings;
  double _staggerDelayMs = 40;
  double _firstNodeDelayMs = 0;
  double _animationDurationMs = 160;
  Curve _animationCurve = Curves.easeOut;
  _TokenAnimationPreset _tokenAnimationPreset =
      _tokenAnimationPresets[_defaultTokenAnimationPresetIndex];
  SelectionStrategy _selectionStrategy = SelectionStrategy.rich;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _systemPromptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _modelController.text = _settings.model;
    _baseUrlController.text = _settings.baseUrl;
    _apiKeyController.text = _settings.apiKey;
    _systemPromptController.text = _settings.systemPrompt;
  }

  void _setProvider(ChatProvider provider) {
    setState(() {
      _settings = ChatConnectionSettings.defaults(
        provider,
      ).copyWith(apiKey: _apiKeyForProvider(provider));
      _syncControllers();
    });
  }

  String _apiKeyForProvider(ChatProvider provider) {
    if (provider == ChatProvider.ollama) {
      return '';
    }
    if (provider == _settings.provider) {
      return _apiKeyController.text.trim();
    }
    return '';
  }

  ChatConnectionSettings _currentSettings() {
    return _settings.copyWith(
      model: _modelController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
    );
  }

  void _submit() {
    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _settings = _currentSettings();
    context.read<ChatBloc>().add(
          ChatSubmitted(question: text, settings: _settings),
        );
    _messageController.clear();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Markdown Chat'),
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
            key: const ValueKey<String>('open_selection_lab'),
            tooltip: 'Open selection lab',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SelectionDemoPage(),
                ),
              );
            },
            icon: const Icon(Icons.ads_click_outlined),
          ),
          BlocBuilder<ChatBloc, ChatState>(
            builder: (BuildContext context, ChatState state) {
              return IconButton(
                tooltip: 'Clear conversation',
                onPressed: state.isSubmitting
                    ? null
                    : () => context.read<ChatBloc>().add(const ChatCleared()),
                icon: const Icon(Icons.delete_outline),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<ChatBloc, ChatState>(
          builder: (BuildContext context, ChatState state) {
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= 960;
                final Widget settingsPanel = _SettingsPanel(
                  settings: _settings,
                  enabled: !state.isSubmitting,
                  modelController: _modelController,
                  baseUrlController: _baseUrlController,
                  apiKeyController: _apiKeyController,
                  systemPromptController: _systemPromptController,
                  staggerDelayMs: _staggerDelayMs,
                  firstNodeDelayMs: _firstNodeDelayMs,
                  animationDurationMs: _animationDurationMs,
                  animationCurve: _animationCurve,
                  tokenAnimationPreset: _tokenAnimationPreset,
                  selectionStrategy: _selectionStrategy,
                  onStaggerDelayChanged: (double value) {
                    setState(() {
                      _staggerDelayMs = value;
                    });
                  },
                  onFirstNodeDelayChanged: (double value) {
                    setState(() {
                      _firstNodeDelayMs = value;
                    });
                  },
                  onAnimationDurationChanged: (double value) {
                    setState(() {
                      _animationDurationMs = value;
                    });
                  },
                  onAnimationCurveChanged: (Curve value) {
                    setState(() {
                      _animationCurve = value;
                    });
                  },
                  onTokenAnimationPresetChanged: (_TokenAnimationPreset value) {
                    setState(() {
                      _tokenAnimationPreset = value;
                    });
                  },
                  onSelectionStrategyChanged: (SelectionStrategy value) {
                    setState(() {
                      _selectionStrategy = value;
                    });
                  },
                  onProviderChanged: _setProvider,
                );
                final Widget chat = _ChatSurface(
                  key: _chatSurfaceKey,
                  scrollController: _scrollController,
                  messageController: _messageController,
                  settings: _currentSettings(),
                  markdownTheme: widget.markdownTheme,
                  renderTiming: _ChatRenderTiming(
                    tokenStaggerDelay: Duration(
                      milliseconds: _staggerDelayMs.round(),
                    ),
                    firstNodeDelay: Duration(
                      milliseconds: _firstNodeDelayMs.round(),
                    ),
                    tokenAnimationDuration: Duration(
                      milliseconds: _animationDurationMs.round(),
                    ),
                    tokenAnimationCurve: _animationCurve,
                    tokenAnimationBuilder: _tokenAnimationPreset.builder,
                    label:
                        '${_staggerDelayMs.round()} ms/token • ${_tokenAnimationPreset.name}',
                  ),
                  selectionStrategy: _selectionStrategy,
                  onSubmit: _submit,
                  onNewContent: _scrollToEnd,
                );

                if (wide) {
                  return Row(
                    children: [
                      SizedBox(width: 360, child: settingsPanel),
                      const VerticalDivider(width: 1),
                      Expanded(child: chat),
                    ],
                  );
                }

                return Column(
                  children: [
                    ExpansionTile(
                      title: Text(
                        '${_settings.provider.label} / ${_modelController.text}',
                      ),
                      leading: const Icon(Icons.tune),
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: settingsPanel,
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(child: chat),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CurveOption {
  const _CurveOption(this.curve, this.name);
  final Curve curve;
  final String name;
}

const List<_CurveOption> _availableCurves = [
  _CurveOption(Curves.linear, 'Linear'),
  _CurveOption(Curves.easeOut, 'Ease out'),
  _CurveOption(Curves.easeIn, 'Ease in'),
  _CurveOption(Curves.easeInOut, 'Ease in out'),
  _CurveOption(Curves.bounceOut, 'Bounce out'),
  _CurveOption(Curves.elasticOut, 'Elastic out'),
];

class _TokenAnimationPreset {
  const _TokenAnimationPreset({required this.name, required this.builder});

  final String name;
  final StreamingMarkdownTokenAnimationBuilder builder;
}

final List<_TokenAnimationPreset> _tokenAnimationPresets =
    <_TokenAnimationPreset>[
  _TokenAnimationPreset(
    name: 'Fade',
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
      final double t = Curves.easeOutBack.transform(token.value);
      return Opacity(
        opacity: Curves.easeOut.transform(token.value),
        child: Transform.translate(
          offset: Offset((1 - t) * -10, 0),
          child: Transform.rotate(
            angle: (1 - t) * -0.42,
            alignment: Alignment.bottomLeft,
            child: Transform.scale(
              scale: 0.94 + (0.06 * t),
              alignment: Alignment.bottomLeft,
              child: token.child,
            ),
          ),
        ),
      );
    },
  ),
  _TokenAnimationPreset(
    name: 'Gravity',
    builder: (BuildContext context, StreamingMarkdownAnimatedToken token) {
      final double fall = Curves.bounceOut.transform(token.value);
      final double fade = Curves.easeOutCubic.transform(token.value);
      return Opacity(
        opacity: fade,
        child: Transform.translate(
          offset: Offset(0, -64 * (1 - fall)),
          child: Transform.scale(
            scale: 0.96 + (0.04 * fall),
            alignment: Alignment.bottomCenter,
            child: token.child,
          ),
        ),
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
];

const List<SelectionStrategy> _selectionStrategies = <SelectionStrategy>[
  SelectionStrategy.rich,
  SelectionStrategy.raw,
  SelectionStrategy.plain,
];

String _selectionStrategyLabel(SelectionStrategy strategy) {
  switch (strategy) {
    case SelectionStrategy.rich:
      return 'Rich HTML';
    case SelectionStrategy.raw:
      return 'Raw Markdown';
    case SelectionStrategy.plain:
      return 'Plain text';
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.settings,
    required this.enabled,
    required this.modelController,
    required this.baseUrlController,
    required this.apiKeyController,
    required this.systemPromptController,
    required this.staggerDelayMs,
    required this.firstNodeDelayMs,
    required this.animationDurationMs,
    required this.animationCurve,
    required this.tokenAnimationPreset,
    required this.selectionStrategy,
    required this.onStaggerDelayChanged,
    required this.onFirstNodeDelayChanged,
    required this.onAnimationDurationChanged,
    required this.onAnimationCurveChanged,
    required this.onTokenAnimationPresetChanged,
    required this.onSelectionStrategyChanged,
    required this.onProviderChanged,
  });

  final ChatConnectionSettings settings;
  final bool enabled;
  final TextEditingController modelController;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController systemPromptController;
  final double staggerDelayMs;
  final double firstNodeDelayMs;
  final double animationDurationMs;
  final Curve animationCurve;
  final _TokenAnimationPreset tokenAnimationPreset;
  final SelectionStrategy selectionStrategy;
  final ValueChanged<double> onStaggerDelayChanged;
  final ValueChanged<double> onFirstNodeDelayChanged;
  final ValueChanged<double> onAnimationDurationChanged;
  final ValueChanged<Curve> onAnimationCurveChanged;
  final ValueChanged<_TokenAnimationPreset> onTokenAnimationPresetChanged;
  final ValueChanged<SelectionStrategy> onSelectionStrategyChanged;
  final ValueChanged<ChatProvider> onProviderChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        DropdownMenu<ChatProvider>(
          initialSelection: settings.provider,
          enabled: enabled,
          label: const Text('Provider'),
          leadingIcon: Icon(
            settings.provider == ChatProvider.ollama
                ? Icons.memory
                : Icons.cloud_queue,
          ),
          dropdownMenuEntries: ChatProvider.values
              .map(
                (ChatProvider provider) => DropdownMenuEntry<ChatProvider>(
                  value: provider,
                  label: provider.label,
                  leadingIcon: Icon(
                    provider == ChatProvider.ollama
                        ? Icons.memory
                        : Icons.cloud_queue,
                  ),
                ),
              )
              .toList(growable: false),
          onSelected: (ChatProvider? provider) {
            if (provider != null) {
              onProviderChanged(provider);
            }
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: modelController,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Model',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: baseUrlController,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: apiKeyController,
          enabled: enabled,
          obscureText: true,
          decoration: InputDecoration(
            labelText: settings.provider == ChatProvider.ollama
                ? 'API key (not needed for Ollama)'
                : 'API key',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: systemPromptController,
          enabled: enabled,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'System prompt',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _TimingSlider(
          label: 'Token reveal interval',
          icon: Icons.speed,
          value: staggerDelayMs,
          min: 0,
          max: 400,
          enabled: enabled,
          onChanged: onStaggerDelayChanged,
        ),
        const SizedBox(height: 16),
        _TimingSlider(
          label: 'First node delay',
          icon: Icons.hourglass_top,
          value: firstNodeDelayMs,
          min: 0,
          max: 1200,
          enabled: enabled,
          onChanged: onFirstNodeDelayChanged,
        ),
        const SizedBox(height: 16),
        _TimingSlider(
          label: 'Token animation duration',
          icon: Icons.bolt,
          value: animationDurationMs,
          min: 0,
          max: 800,
          enabled: enabled,
          onChanged: onAnimationDurationChanged,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<_TokenAnimationPreset>(
          // ignore: deprecated_member_use
          value: tokenAnimationPreset,
          decoration: const InputDecoration(
            labelText: 'Token animation style',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.auto_awesome_motion_outlined),
          ),
          items: _tokenAnimationPresets.map((_TokenAnimationPreset opt) {
            return DropdownMenuItem<_TokenAnimationPreset>(
              value: opt,
              child: Text(opt.name),
            );
          }).toList(),
          onChanged: enabled
              ? (_TokenAnimationPreset? value) {
                  if (value != null) {
                    onTokenAnimationPresetChanged(value);
                  }
                }
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Curve>(
          // ignore: deprecated_member_use
          value: animationCurve,
          decoration: const InputDecoration(
            labelText: 'Animation curve',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.trending_up),
          ),
          items: _availableCurves.map((opt) {
            return DropdownMenuItem<Curve>(
              value: opt.curve,
              child: Text(opt.name),
            );
          }).toList(),
          onChanged: enabled
              ? (Curve? value) {
                  if (value != null) {
                    onAnimationCurveChanged(value);
                  }
                }
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<SelectionStrategy>(
          // ignore: deprecated_member_use
          value: selectionStrategy,
          decoration: const InputDecoration(
            labelText: 'Copy strategy',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.copy_all_outlined),
          ),
          items: _selectionStrategies.map((SelectionStrategy strategy) {
            return DropdownMenuItem<SelectionStrategy>(
              value: strategy,
              child: Text(_selectionStrategyLabel(strategy)),
            );
          }).toList(),
          onChanged: enabled
              ? (SelectionStrategy? value) {
                  if (value != null) {
                    onSelectionStrategyChanged(value);
                  }
                }
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          _providerHint(settings.provider),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _providerHint(ChatProvider provider) {
    return switch (provider) {
      ChatProvider.ollama =>
        'Run `ollama serve`, then pull a model such as `ollama pull batiai/gemma4-e4b:q4`.',
      ChatProvider.openai =>
        'Uses OpenAI-compatible `/v1/chat/completions` streaming.',
      ChatProvider.anthropic =>
        'Uses Anthropic Messages streaming with `anthropic-version: 2023-06-01`.',
      ChatProvider.gemini => 'Uses Gemini `streamGenerateContent` with SSE.',
      ChatProvider.xai =>
        'Uses xAI OpenAI-compatible `/v1/chat/completions` streaming.',
    };
  }
}

class _ChatSurface extends StatefulWidget {
  const _ChatSurface({
    super.key,
    required this.scrollController,
    required this.messageController,
    required this.settings,
    required this.markdownTheme,
    required this.renderTiming,
    required this.selectionStrategy,
    required this.onSubmit,
    required this.onNewContent,
  });

  final ScrollController scrollController;
  final TextEditingController messageController;
  final ChatConnectionSettings settings;
  final AnimatedMarkdownThemeData markdownTheme;
  final _ChatRenderTiming renderTiming;
  final SelectionStrategy selectionStrategy;
  final VoidCallback onSubmit;
  final VoidCallback onNewContent;

  @override
  State<_ChatSurface> createState() => _ChatSurfaceState();
}

class _ChatSurfaceState extends State<_ChatSurface> {
  final GlobalKey _conversationKey = GlobalKey();
  final Set<String> _settledAssistantIds = <String>{};

  bool _canSubmit(ChatState state) {
    if (state.isSubmitting) {
      return false;
    }
    for (final ChatMessage message in state.messages) {
      if (message.role != 'assistant') {
        continue;
      }
      if (!message.complete || !_settledAssistantIds.contains(message.id)) {
        return false;
      }
    }
    return true;
  }

  bool _hasIncompleteAssistant(ChatState state) {
    for (final ChatMessage message in state.messages) {
      if (message.role == 'assistant' && !message.complete) {
        return true;
      }
    }
    return false;
  }

  bool _hasUnsettledAssistant(ChatState state) {
    for (final ChatMessage message in state.messages) {
      if (message.role != 'assistant') {
        continue;
      }
      if (!_settledAssistantIds.contains(message.id)) {
        return true;
      }
    }
    return false;
  }

  String _effectiveStatus(ChatState state) {
    if (_hasIncompleteAssistant(state)) {
      return 'Streaming and rendering...';
    }
    if (_hasUnsettledAssistant(state)) {
      return 'Finishing render...';
    }
    return state.status;
  }

  void _syncSettledMessages(ChatState state) {
    final Set<String> activeAssistantIds = state.messages
        .where((ChatMessage message) => message.role == 'assistant')
        .map((ChatMessage message) => message.id)
        .toSet();
    final Set<String> before = Set<String>.of(_settledAssistantIds);
    _settledAssistantIds.removeWhere(
      (String id) => !activeAssistantIds.contains(id),
    );
    for (final ChatMessage message in state.messages) {
      if (message.role == 'assistant' && !message.complete) {
        _settledAssistantIds.remove(message.id);
      }
    }
    if (before.length != _settledAssistantIds.length && mounted) {
      setState(() {});
    }
  }

  void _markAssistantSettled(String id) {
    if (_settledAssistantIds.contains(id)) {
      return;
    }
    setState(() {
      _settledAssistantIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatBloc, ChatState>(
      listener: (BuildContext context, ChatState state) {
        _syncSettledMessages(state);
        widget.onNewContent();
      },
      builder: (BuildContext context, ChatState state) {
        final bool canSubmit = _canSubmit(state);
        final String rawMarkdown = _latestAssistantMarkdown(state);
        final Widget conversation = state.messages.isEmpty
            ? _EmptyChat(provider: widget.settings.provider)
            : ListView.builder(
                key: const PageStorageKey<String>('chat_message_list'),
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: state.messages.length,
                findChildIndexCallback: (Key key) {
                  if (key is! ValueKey<String>) {
                    return null;
                  }
                  final String value = key.value;
                  if (!value.startsWith('message_')) {
                    return null;
                  }
                  final String id = value.substring('message_'.length);
                  final int index = state.messages.indexWhere(
                    (ChatMessage message) => message.id == id,
                  );
                  return index < 0 ? null : index;
                },
                itemBuilder: (BuildContext context, int index) {
                  final ChatMessage message = state.messages[index];
                  return _MessageBubble(
                    key: ValueKey<String>('message_${message.id}'),
                    message: message,
                    markdownTheme: widget.markdownTheme,
                    renderTiming: widget.renderTiming,
                    selectionStrategy: widget.selectionStrategy,
                    onAssistantSettled: () {
                      _markAssistantSettled(message.id);
                    },
                  );
                },
              );
        final Widget stableConversation = KeyedSubtree(
          key: _conversationKey,
          child: conversation,
        );
        return Column(
          children: [
            _StatusBar(
              status: _effectiveStatus(state),
              settings: widget.settings,
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  if (constraints.maxWidth < 860) {
                    return stableConversation;
                  }
                  return Row(
                    children: [
                      Expanded(child: stableConversation),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 360,
                        child: _RawMarkdownPane(markdown: rawMarkdown),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            _Composer(
              controller: widget.messageController,
              enabled: canSubmit,
              onSubmit: widget.onSubmit,
            ),
          ],
        );
      },
    );
  }

  String _latestAssistantMarkdown(ChatState state) {
    for (final ChatMessage message in state.messages.reversed) {
      if (message.role == 'assistant') {
        return message.content;
      }
    }
    return '';
  }
}

class _RawMarkdownPane extends StatelessWidget {
  const _RawMarkdownPane({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final TextStyle codeStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.45,
            ) ??
        const TextStyle(fontFamily: 'monospace', height: 1.45);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Raw Markdown',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                markdown.isEmpty ? 'No assistant markdown yet.' : markdown,
                style: codeStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status, required this.settings});

  final String status;
  final ChatConnectionSettings settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            settings.provider == ChatProvider.ollama
                ? Icons.memory
                : Icons.cloud_queue,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${settings.provider.label} • ${settings.model} • $status',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.provider});

  final ChatProvider provider;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                provider == ChatProvider.ollama
                    ? Icons.terminal
                    : Icons.chat_bubble_outline,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                'Ask for Markdown, code, tables, lists, LaTeX, or streaming edge cases.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'The assistant response is streamed and rendered with AnimatedStreamingMarkdown.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.markdownTheme,
    required this.renderTiming,
    required this.selectionStrategy,
    required this.onAssistantSettled,
  });

  final ChatMessage message;
  final AnimatedMarkdownThemeData markdownTheme;
  final _ChatRenderTiming renderTiming;
  final SelectionStrategy selectionStrategy;
  final VoidCallback onAssistantSettled;

  @override
  Widget build(BuildContext context) {
    final bool user = message.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: user
                ? Theme.of(context).colorScheme.primaryContainer
                : flutterSurfaceContainerHighest(
                    Theme.of(context).colorScheme,
                  ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: user
              ? SelectableText(
                  message.content,
                  key: ValueKey<String>('user_text_${message.id}'),
                )
              : _AssistantMarkdownBubble(
                  key: ValueKey<String>('assistant_markdown_${message.id}'),
                  markdown: message.content,
                  tokenStaggerDelay: renderTiming.tokenStaggerDelay,
                  firstNodeDelay: renderTiming.firstNodeDelay,
                  tokenAnimationDuration: renderTiming.tokenAnimationDuration,
                  tokenAnimationCurve: renderTiming.tokenAnimationCurve,
                  tokenAnimationBuilder: renderTiming.tokenAnimationBuilder,
                  responseComplete: message.complete,
                  enableSelection: true,
                  selectionStrategy: selectionStrategy,
                  onRenderSettled: onAssistantSettled,
                  theme: markdownTheme,
                ),
        ),
      ),
    );
  }
}

class _AssistantMarkdownBubble extends StatefulWidget {
  const _AssistantMarkdownBubble({
    super.key,
    required this.markdown,
    required this.tokenStaggerDelay,
    required this.firstNodeDelay,
    required this.tokenAnimationDuration,
    required this.tokenAnimationCurve,
    required this.tokenAnimationBuilder,
    required this.responseComplete,
    required this.enableSelection,
    required this.selectionStrategy,
    required this.onRenderSettled,
    required this.theme,
  });

  final String markdown;
  final Duration tokenStaggerDelay;
  final Duration firstNodeDelay;
  final Duration tokenAnimationDuration;
  final Curve tokenAnimationCurve;
  final StreamingMarkdownTokenAnimationBuilder tokenAnimationBuilder;
  final bool responseComplete;
  final bool enableSelection;
  final SelectionStrategy selectionStrategy;
  final VoidCallback onRenderSettled;
  final AnimatedMarkdownThemeData theme;

  @override
  State<_AssistantMarkdownBubble> createState() =>
      _AssistantMarkdownBubbleState();
}

class _AssistantMarkdownBubbleState extends State<_AssistantMarkdownBubble>
    with AutomaticKeepAliveClientMixin<_AssistantMarkdownBubble> {
  final MarkdownStreamParser _parser = MarkdownStreamParser();
  final Queue<String> _pendingSegments = Queue<String>();

  List<MarkdownBlock> _blocks = const <MarkdownBlock>[];
  String _sourceMarkdown = '';
  String _parsedMarkdown = '';
  bool _parserStarted = false;
  bool _syncing = false;
  int _generation = 0;
  bool _waitingFirstNodeDelay = false;
  bool _sequenceSettled = false;
  Timer? _settledTimer;
  String? _settledSignature;
  String? _error;

  // A chat message is a long-lived document, even while it is outside the
  // ListView cache extent. Without keep-alive Flutter disposes this state and
  // recreates the parser plus token animation when the user scrolls back or a
  // new message pushes it off-screen.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_startParser());
  }

  @override
  void didUpdateWidget(_AssistantMarkdownBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      _cancelSettledTimer();
      _settledSignature = null;
      _syncIncomingMarkdown();
    } else if (oldWidget.tokenStaggerDelay != widget.tokenStaggerDelay ||
        oldWidget.firstNodeDelay != widget.firstNodeDelay ||
        oldWidget.tokenAnimationDuration != widget.tokenAnimationDuration ||
        oldWidget.tokenAnimationCurve != widget.tokenAnimationCurve ||
        oldWidget.tokenAnimationBuilder != widget.tokenAnimationBuilder) {
      _cancelSettledTimer();
      _settledSignature = null;
      _sequenceSettled = false;
      _schedulePump();
    }
    if (!oldWidget.responseComplete && widget.responseComplete) {
      _scheduleSettledNotification();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _cancelSettledTimer();
    _parser.dispose();
    super.dispose();
  }

  Future<void> _startParser() async {
    try {
      await _parser.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _parserStarted = true;
      });
      _syncIncomingMarkdown();
      _scheduleSettledNotification();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  void _syncIncomingMarkdown() {
    if (!_parserStarted) {
      return;
    }

    final String incoming = widget.markdown;
    if (incoming.isEmpty) {
      _resetRenderedMarkdown();
      return;
    }

    if (_sourceMarkdown.isNotEmpty && !incoming.startsWith(_sourceMarkdown)) {
      _replaceWithIncomingMarkdown(incoming);
      return;
    }

    if (incoming.length < _sourceMarkdown.length) {
      _replaceWithIncomingMarkdown(incoming);
      return;
    }

    if (incoming.length <= _sourceMarkdown.length) {
      return;
    }

    final String delta = incoming.substring(_sourceMarkdown.length);
    _notifyRenderActivity();
    _sourceMarkdown = incoming;
    _pendingSegments.add(delta);
    _schedulePump();
  }

  void _resetRenderedMarkdown() {
    _generation += 1;
    _cancelSettledTimer();
    _settledSignature = null;
    _pendingSegments.clear();
    _waitingFirstNodeDelay = false;
    _sequenceSettled = false;
    _sourceMarkdown = '';
    _parsedMarkdown = '';
    _syncing = false;
    setState(() {
      _blocks = const <MarkdownBlock>[];
      _error = null;
    });
    unawaited(_replaceParserText(''));
  }

  void _replaceWithIncomingMarkdown(String incoming) {
    _generation += 1;
    _cancelSettledTimer();
    _settledSignature = null;
    _pendingSegments.clear();
    _waitingFirstNodeDelay = false;
    _sequenceSettled = false;
    _notifyRenderActivity();
    _sourceMarkdown = incoming;
    _parsedMarkdown = incoming;
    _syncing = false;
    unawaited(_replaceParserText(incoming));
  }

  Future<void> _replaceParserText(String text) async {
    try {
      final MarkdownParseResult result = await _parser.replace(text);
      if (!mounted || text != _parsedMarkdown) {
        return;
      }
      setState(() {
        _blocks = result.blocks;
        _error = null;
      });
      _scheduleSettledNotification();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  void _schedulePump() {
    if (!_parserStarted || _syncing) {
      return;
    }
    _syncing = true;
    final int generation = _generation;
    unawaited(_pumpSegments(generation));
  }

  Future<void> _pumpSegments(int generation) async {
    try {
      while (
          mounted && generation == _generation && _pendingSegments.isNotEmpty) {
        if (_parsedMarkdown.isEmpty &&
            !_waitingFirstNodeDelay &&
            widget.firstNodeDelay > Duration.zero &&
            widget.markdown.isNotEmpty) {
          _waitingFirstNodeDelay = true;
          await Future<void>.delayed(widget.firstNodeDelay);
          if (!mounted || generation != _generation) {
            return;
          }
          _waitingFirstNodeDelay = false;
        }

        final String segment = _pendingSegments.removeFirst();
        final MarkdownParseResult result = await _parser.append(segment);
        if (!mounted) {
          return;
        }
        setState(() {
          _parsedMarkdown += segment;
          _blocks = result.blocks;
          _error = null;
        });
        _notifyRenderActivity();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      _syncing = false;
      if (mounted && _pendingSegments.isNotEmpty) {
        _schedulePump();
      } else {
        _scheduleSettledNotification();
      }
    }
  }

  void _scheduleSettledNotification() {
    if (!mounted ||
        !widget.responseComplete ||
        _syncing ||
        _waitingFirstNodeDelay ||
        !_sequenceSettled ||
        _pendingSegments.isNotEmpty ||
        _parsedMarkdown != widget.markdown) {
      return;
    }

    final String signature = Object.hashAll(<Object?>[
      widget.markdown,
      widget.tokenStaggerDelay,
      widget.tokenAnimationDuration,
      widget.tokenAnimationCurve,
      widget.tokenAnimationBuilder,
    ]).toString();
    if (_settledSignature == signature) {
      return;
    }

    _cancelSettledTimer();
    _settledTimer = Timer(_settleQuietWindow(), () async {
      if (!mounted ||
          _syncing ||
          _waitingFirstNodeDelay ||
          !_sequenceSettled ||
          _pendingSegments.isNotEmpty ||
          _parsedMarkdown != widget.markdown ||
          !widget.responseComplete) {
        _scheduleSettledNotification();
        return;
      }
      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted ||
          _syncing ||
          _waitingFirstNodeDelay ||
          !_sequenceSettled ||
          _pendingSegments.isNotEmpty ||
          _parsedMarkdown != widget.markdown ||
          !widget.responseComplete) {
        _scheduleSettledNotification();
        return;
      }
      _settledSignature = signature;
      widget.onRenderSettled();
    });
  }

  void _cancelSettledTimer() {
    _settledTimer?.cancel();
    _settledTimer = null;
  }

  void _notifyRenderActivity() {
    if (widget.responseComplete) {
      _cancelSettledTimer();
      _settledSignature = null;
      _scheduleSettledNotification();
    }
  }

  Duration _settleQuietWindow() {
    final Duration tail = widget.tokenStaggerDelay * 8;
    final Duration raw = tail > widget.tokenAnimationDuration
        ? tail
        : widget.tokenAnimationDuration;
    const Duration floor = Duration(milliseconds: 160);
    const Duration ceiling = Duration(seconds: 3);
    if (raw < floor) {
      return floor;
    }
    if (raw > ceiling) {
      return ceiling;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) {
      return SelectableText('Render failed:\n\n$_error');
    }
    if (widget.markdown.isEmpty) {
      return const Text('Thinking...');
    }
    if (_blocks.isEmpty) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return RepaintBoundary(
      child: AnimatedStreamingMarkdown(
        key: const ValueKey<String>('assistant_streaming_markdown_view'),
        blocks: _blocks,
        allowIncompleteInlineSyntax: true,
        tokenStaggerDelay: widget.tokenStaggerDelay,
        onTokenDelay: _notifyRenderActivity,
        onTokenAnimationEnd: _notifyRenderActivity,
        onSequenceSettled: () {
          _sequenceSettled = true;
          _scheduleSettledNotification();
        },
        tokenAnimationDuration: widget.tokenAnimationDuration,
        tokenAnimationCurve: widget.tokenAnimationCurve,
        tokenAnimationBuilder: widget.tokenAnimationBuilder,
        enableSelection: widget.enableSelection,
        selectionStrategy: widget.selectionStrategy,
        showCodeBlockCopyButton: true,
        theme: widget.theme,
      ),
    );
  }
}

class _TimingSlider extends StatelessWidget {
  const _TimingSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: enabled ? null : Theme.of(context).disabledColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  color: enabled ? null : Theme.of(context).disabledColor,
                ),
              ),
            ),
            Text(
              '${value.round()} ms',
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: max > min ? (max - min) ~/ 10 : 1,
          label: '${value.round()} ms',
          onChanged: enabled ? onChanged : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${min.round()} ms',
              style: textTheme.bodySmall?.copyWith(
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
            ),
            Text(
              '${((min + max) / 2).round()} ms',
              style: textTheme.bodySmall?.copyWith(
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
            ),
            Text(
              '${max.round()} ms',
              style: textTheme.bodySmall?.copyWith(
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatRenderTiming {
  const _ChatRenderTiming({
    required this.tokenStaggerDelay,
    required this.firstNodeDelay,
    required this.tokenAnimationDuration,
    required this.tokenAnimationCurve,
    required this.tokenAnimationBuilder,
    required this.label,
  });

  final Duration tokenStaggerDelay;
  final Duration firstNodeDelay;
  final Duration tokenAnimationDuration;
  final Curve tokenAnimationCurve;
  final StreamingMarkdownTokenAnimationBuilder tokenAnimationBuilder;
  final String label;
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Ask something...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: enabled ? onSubmit : null,
            icon: enabled
                ? const Icon(Icons.send)
                : const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
