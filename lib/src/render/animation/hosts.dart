part of '../view.dart';

class _BlockRenderHost extends StatefulWidget {
  const _BlockRenderHost({
    super.key,
    required this.signature,
    required this.node,
    required this.linkReferences,
    required this.footnoteNumbers,
    required this.builder,
  });

  final String signature;
  final MarkdownRenderNode node;
  final Map<String, String> linkReferences;
  final Map<String, int> footnoteNumbers;
  final _BlockBuilder builder;

  @override
  State<_BlockRenderHost> createState() => _BlockRenderHostState();
}

class _RevealScheduleScope extends InheritedWidget {
  const _RevealScheduleScope({
    required super.child,
    required this.revealedAt,
    required this.tokenArrivalDelay,
    required this.paused,
  });

  final DateTime? revealedAt;
  final Duration tokenArrivalDelay;
  final bool paused;

  static _RevealScheduleScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_RevealScheduleScope>();
  }

  @override
  bool updateShouldNotify(_RevealScheduleScope oldWidget) {
    return oldWidget.revealedAt != revealedAt ||
        oldWidget.tokenArrivalDelay != tokenArrivalDelay ||
        oldWidget.paused != paused;
  }
}

class _BlockRenderHostState extends State<_BlockRenderHost>
    with AutomaticKeepAliveClientMixin<_BlockRenderHost> {
  String? _cachedSignature;
  Widget? _cachedChild;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _BlockRenderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      _cachedSignature = null;
      _cachedChild = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cachedChild == null || _cachedSignature != widget.signature) {
      _cachedChild = widget.builder(
        context,
        widget.node,
        widget.linkReferences,
        widget.footnoteNumbers,
      );
      _cachedSignature = widget.signature;
    }
    return RepaintBoundary(child: _cachedChild!);
  }
}

class _TokenLayoutGate extends StatefulWidget {
  const _TokenLayoutGate({
    this.initialDelay = Duration.zero,
    this.scheduledStart,
    required this.child,
  });

  final Duration initialDelay;
  final DateTime? scheduledStart;
  final Widget child;

  @override
  State<_TokenLayoutGate> createState() => _TokenLayoutGateState();
}

class _TokenLayoutGateState extends State<_TokenLayoutGate> {
  bool _visible = false;
  Timer? _timer;
  DateTime? _timerStartedAt;
  Duration? _timerDelay;
  Duration? _pausedDelay;
  bool _paused = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _TokenLayoutGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDelay != widget.initialDelay ||
        oldWidget.scheduledStart != widget.scheduledStart) {
      _configure();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool paused = _RevealScheduleScope.maybeOf(context)?.paused ?? false;
    if (!_configured) {
      _paused = paused;
      _configured = true;
      _configure();
      return;
    }
    if (_paused == paused) {
      return;
    }
    _paused = paused;
    if (_paused) {
      _pauseTimer();
    } else {
      _resumeTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _configure() {
    _timer?.cancel();
    _timer = null;
    _timerStartedAt = null;
    _timerDelay = null;
    _pausedDelay = null;

    final DateTime now = DateTime.now();
    final Duration sanitizedDelay = widget.initialDelay <= Duration.zero
        ? Duration.zero
        : widget.initialDelay;
    final DateTime scheduledStart =
        widget.scheduledStart ?? now.add(sanitizedDelay);

    if (!now.isBefore(scheduledStart)) {
      if (_paused) {
        _visible = false;
        _pausedDelay = Duration.zero;
        return;
      }
      _visible = true;
      return;
    }

    _visible = false;
    final Duration delay = scheduledStart.difference(now);
    if (_paused) {
      _pausedDelay = delay;
      return;
    }
    _startTimer(delay);
  }

  void _startTimer(Duration delay) {
    _timerStartedAt = DateTime.now();
    _timerDelay = delay;
    _timer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      _timer = null;
      _timerStartedAt = null;
      _timerDelay = null;
      setState(() {
        _visible = true;
      });
    });
  }

  void _pauseTimer() {
    final Timer? timer = _timer;
    if (timer == null || _visible) {
      return;
    }
    timer.cancel();
    _timer = null;
    final DateTime? startedAt = _timerStartedAt;
    final Duration? delay = _timerDelay;
    if (startedAt == null || delay == null) {
      _pausedDelay = Duration.zero;
      return;
    }
    final Duration remaining = delay - DateTime.now().difference(startedAt);
    _pausedDelay = remaining <= Duration.zero ? Duration.zero : remaining;
    _timerStartedAt = null;
    _timerDelay = null;
  }

  void _resumeTimer() {
    if (_visible) {
      return;
    }
    final Duration? delay = _pausedDelay;
    _pausedDelay = null;
    if (delay == null) {
      _configure();
      return;
    }
    if (delay <= Duration.zero) {
      setState(() {
        _visible = true;
      });
      return;
    }
    _startTimer(delay);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}
