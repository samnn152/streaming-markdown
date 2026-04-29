part of '../view.dart';

class _FadeInTokenHost extends StatefulWidget {
  const _FadeInTokenHost({
    this.initialDelay = Duration.zero,
    this.scheduledStart,
    required this.duration,
    required this.curve,
    this.animationBuilder,
    this.onFadeInEnd,
    required this.child,
    super.key,
  });

  final Duration initialDelay;
  final DateTime? scheduledStart;
  final Duration duration;
  final Curve curve;
  final StreamingMarkdownTokenAnimationBuilder? animationBuilder;
  final VoidCallback? onFadeInEnd;
  final Widget child;

  @override
  State<_FadeInTokenHost> createState() => _FadeInTokenHostState();
}

class _FadeInTokenHostState extends State<_FadeInTokenHost> {
  bool _revealed = false;
  bool _animationCompleted = false;
  Duration _animationDuration = Duration.zero;
  double _beginOpacity = 0;
  double _currentOpacity = 0;
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
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool paused = _RevealScheduleScope.maybeOf(context)?.paused ?? false;
    if (!_configured) {
      _paused = paused;
      _configured = true;
      _configureSchedule();
      return;
    }
    if (_paused == paused) {
      return;
    }
    _paused = paused;
    if (_paused) {
      _pause();
    } else {
      _resume();
    }
  }

  void _configureSchedule() {
    _timer?.cancel();
    _timer = null;
    _timerStartedAt = null;
    _timerDelay = null;
    _pausedDelay = null;

    if (widget.duration <= Duration.zero) {
      _revealed = true;
      _animationCompleted = true;
      _animationDuration = Duration.zero;
      _beginOpacity = 1;
      _currentOpacity = 1;
      return;
    }

    final DateTime now = DateTime.now();
    final Duration sanitizedDelay = widget.initialDelay <= Duration.zero
        ? Duration.zero
        : widget.initialDelay;
    final DateTime scheduledStart =
        widget.scheduledStart ?? now.add(sanitizedDelay);

    if (now.isBefore(scheduledStart)) {
      _revealed = false;
      _animationCompleted = false;
      _animationDuration = widget.duration;
      _beginOpacity = 0;
      _currentOpacity = 0;
      final Duration delay = scheduledStart.difference(now);
      if (_paused) {
        _pausedDelay = delay;
      } else {
        _startTimer(delay);
      }
      return;
    }

    if (_paused) {
      _revealed = false;
      _animationCompleted = false;
      _animationDuration = widget.duration;
      _beginOpacity = 0;
      _currentOpacity = 0;
      _pausedDelay = Duration.zero;
      return;
    }

    // Do not "catch up" to partial progress when built late.
    // Each token should start from 0 opacity once it becomes visible.
    _revealed = true;
    _animationCompleted = false;
    _animationDuration = widget.duration;
    _beginOpacity = 0;
    _currentOpacity = 0;
  }

  void _startTimer(Duration delay) {
    _timerStartedAt = DateTime.now();
    _timerDelay = delay;
    _timer = Timer(delay, _startAnimationNow);
  }

  void _startAnimationNow() {
    if (!mounted) {
      return;
    }
    setState(() {
      _revealed = true;
      _animationCompleted = false;
      _animationDuration = widget.duration;
      _beginOpacity = 0;
      _currentOpacity = 0;
    });
  }

  void _pause() {
    final Timer? timer = _timer;
    if (timer != null && !_revealed) {
      timer.cancel();
      _timer = null;
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
      return;
    }

    if (_revealed && !_animationCompleted) {
      final double remainingFraction = (1 - _currentOpacity).clamp(0.0, 1.0);
      final int remainingMicros =
          (widget.duration.inMicroseconds * remainingFraction).round();
      setState(() {
        _beginOpacity = _currentOpacity;
        _animationDuration = Duration(microseconds: remainingMicros);
      });
    }
  }

  void _resume() {
    if (!_revealed) {
      final Duration? delay = _pausedDelay;
      _pausedDelay = null;
      if (delay == null) {
        _configureSchedule();
        return;
      }
      if (delay <= Duration.zero) {
        _startAnimationNow();
      } else {
        _startTimer(delay);
      }
      return;
    }

    if (!_animationCompleted) {
      setState(() {
        _beginOpacity = _currentOpacity;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duration <= Duration.zero) {
      return widget.child;
    }
    if (!_revealed) {
      return const Offstage(offstage: true);
    }
    if (_animationCompleted || _animationDuration <= Duration.zero) {
      return widget.child;
    }
    if (_paused) {
      return _buildAnimatedChild(_currentOpacity, widget.child);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _beginOpacity, end: 1),
      duration: _animationDuration,
      curve: widget.curve,
      child: widget.child,
      onEnd: () {
        if (!mounted || _animationCompleted) {
          return;
        }
        setState(() {
          _animationCompleted = true;
        });
        widget.onFadeInEnd?.call();
      },
      builder: (BuildContext context, double opacity, Widget? child) {
        _currentOpacity = opacity;
        return _buildAnimatedChild(opacity, child ?? widget.child);
      },
    );
  }

  Widget _buildAnimatedChild(double opacity, Widget child) {
    final StreamingMarkdownTokenAnimationBuilder? builder =
        widget.animationBuilder;
    if (builder == null) {
      return Opacity(opacity: opacity, child: child);
    }
    return builder(
      context,
      StreamingMarkdownAnimatedToken(
        child: child,
        animation: AlwaysStoppedAnimation<double>(opacity),
      ),
    );
  }
}
