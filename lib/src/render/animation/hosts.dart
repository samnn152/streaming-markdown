part of '../view.dart';

class _BlockRenderHost extends StatefulWidget {
  const _BlockRenderHost({
    super.key,
    required this.signature,
    required this.node,
    required this.linkReferences,
    required this.footnoteNumbers,
    required this.compactSettledTokens,
    required this.compactionDelay,
    required this.builder,
  });

  final String signature;
  final MarkdownRenderNode node;
  final Map<String, String> linkReferences;
  final Map<String, int> footnoteNumbers;
  final bool compactSettledTokens;
  final Duration compactionDelay;
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
  bool _compacted = false;
  Timer? _compactionTimer;
  DateTime? _timerStartedAt;
  Duration? _timerDelay;
  Duration? _pausedDelay;
  bool _paused = false;
  DateTime? _scheduledForReveal;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _BlockRenderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      _cachedSignature = null;
      _cachedChild = null;
      _compacted = false;
      _cancelCompactionTimer();
    }
  }

  @override
  void dispose() {
    _cancelCompactionTimer();
    super.dispose();
  }

  void _cancelCompactionTimer() {
    _compactionTimer?.cancel();
    _compactionTimer = null;
    _timerStartedAt = null;
    _timerDelay = null;
    _pausedDelay = null;
    _scheduledForReveal = null;
  }

  void _syncCompactionSchedule(BuildContext context) {
    final _RevealScheduleScope? revealScope = _RevealScheduleScope.maybeOf(
      context,
    );
    final bool paused = revealScope?.paused ?? false;
    if (!widget.compactSettledTokens) {
      if (_compacted || _compactionTimer != null) {
        _cancelCompactionTimer();
        _compacted = false;
        _cachedChild = null;
      }
      _paused = paused;
      return;
    }
    if (_compacted) {
      _paused = paused;
      return;
    }
    final DateTime revealedAt = revealScope?.revealedAt ?? DateTime.now();
    if (_scheduledForReveal != revealedAt) {
      _cancelCompactionTimer();
      _scheduledForReveal = revealedAt;
    }
    if (!_paused && paused) {
      _paused = true;
      _pauseCompactionTimer();
      return;
    }
    if (_paused && !paused) {
      _paused = false;
      _resumeCompactionTimer();
      return;
    }
    _paused = paused;
    if (_paused || _compactionTimer != null) {
      return;
    }
    final Duration delay = widget.compactionDelay;
    final DateTime compactAt = revealedAt.add(delay);
    final Duration remaining = compactAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _scheduleCompaction();
      return;
    }
    _startCompactionTimer(remaining);
  }

  void _startCompactionTimer(Duration delay) {
    _timerStartedAt = DateTime.now();
    _timerDelay = delay;
    _compactionTimer = Timer(delay, () {
      _compactionTimer = null;
      _timerStartedAt = null;
      _timerDelay = null;
      _scheduleCompaction();
    });
  }

  void _pauseCompactionTimer() {
    final Timer? timer = _compactionTimer;
    if (timer == null) {
      return;
    }
    timer.cancel();
    _compactionTimer = null;
    final DateTime? startedAt = _timerStartedAt;
    final Duration? delay = _timerDelay;
    if (startedAt == null || delay == null) {
      _pausedDelay = Duration.zero;
    } else {
      final Duration remaining = delay - DateTime.now().difference(startedAt);
      _pausedDelay = remaining <= Duration.zero ? Duration.zero : remaining;
    }
    _timerStartedAt = null;
    _timerDelay = null;
  }

  void _resumeCompactionTimer() {
    final Duration? delay = _pausedDelay;
    _pausedDelay = null;
    if (delay == null) {
      return;
    }
    if (delay <= Duration.zero) {
      _scheduleCompaction();
      return;
    }
    _startCompactionTimer(delay);
  }

  void _scheduleCompaction() {
    if (_compacted || !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _compacted || !widget.compactSettledTokens) {
        return;
      }
      setState(() {
        _compacted = true;
        _cachedChild = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _syncCompactionSchedule(context);
    if (_cachedChild == null || _cachedSignature != widget.signature) {
      _cachedChild = _TokenCompactionScope(
        compacted: _compacted,
        child: Builder(
          builder: (BuildContext context) {
            return widget.builder(
              context,
              widget.node,
              widget.linkReferences,
              widget.footnoteNumbers,
            );
          },
        ),
      );
      _cachedSignature = widget.signature;
    }
    return RepaintBoundary(child: _cachedChild!);
  }
}

class _TokenCompactionScope extends InheritedWidget {
  const _TokenCompactionScope({
    required this.compacted,
    required super.child,
  });

  final bool compacted;

  static bool isCompacted(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_TokenCompactionScope>()
            ?.compacted ??
        false;
  }

  @override
  bool updateShouldNotify(_TokenCompactionScope oldWidget) {
    return oldWidget.compacted != compacted;
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
