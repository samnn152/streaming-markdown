part of '../view.dart';

class _SequencedBlockListState extends State<_SequencedBlockList> {
  final Set<String> _visibleIds = <String>{};
  final LinkedHashSet<String> _pendingIds = LinkedHashSet<String>();
  final Map<String, DateTime> _revealedAt = <String, DateTime>{};
  Timer? _revealTimer;
  DateTime? _revealTimerStartedAt;
  Duration? _revealTimerDelay;
  Duration? _pausedRevealDelay;
  bool _isWaiting = false;

  @override
  void initState() {
    super.initState();
    _syncSchedule();
  }

  @override
  void didUpdateWidget(covariant _SequencedBlockList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.paused && widget.paused) {
      _syncSchedule();
      _pauseRevealTimer();
      return;
    }
    if (oldWidget.paused && !widget.paused) {
      _syncSchedule();
      _resumeRevealTimer();
      return;
    }
    _syncSchedule();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _syncSchedule() {
    final List<String> orderedIds =
        widget.blocks.map(widget.blockIdentityBuilder).toList(growable: false);
    final Set<String> activeIds = orderedIds.toSet();

    _visibleIds.removeWhere((String id) => !activeIds.contains(id));
    _pendingIds.removeWhere((String id) => !activeIds.contains(id));
    _revealedAt.removeWhere((String id, DateTime _) => !activeIds.contains(id));

    if (orderedIds.isEmpty) {
      _revealTimer?.cancel();
      _revealTimer = null;
      _revealTimerStartedAt = null;
      _revealTimerDelay = null;
      _pausedRevealDelay = null;
      _pendingIds.clear();
      if (_visibleIds.isNotEmpty && mounted) {
        setState(() {
          _visibleIds.clear();
        });
      } else {
        _visibleIds.clear();
      }
      _isWaiting = false;
      return;
    }

    bool queuedNew = false;
    for (final String id in orderedIds) {
      if (_visibleIds.contains(id) || _pendingIds.contains(id)) {
        continue;
      }
      _pendingIds.add(id);
      queuedNew = true;
    }

    if (queuedNew) {
      _isWaiting = false;
      if (!widget.paused && _revealTimer == null) {
        _drainQueue();
      }
      return;
    }

    if (!widget.paused && _pendingIds.isEmpty && _revealTimer == null) {
      _enterWaiting();
    }
  }

  void _drainQueue() {
    if (!mounted || widget.paused) {
      return;
    }
    if (_pendingIds.isEmpty) {
      _enterWaiting();
      return;
    }

    final String nextId = _pendingIds.first;
    _pendingIds.remove(nextId);
    final MarkdownRenderNode? revealedNode = _nodeForId(nextId);
    final DateTime revealedAt = DateTime.now();
    setState(() {
      _visibleIds.add(nextId);
      _revealedAt[nextId] = revealedAt;
    });

    if (_pendingIds.isEmpty) {
      _enterWaiting();
      return;
    }

    final Duration delay = _nextDequeueDelayAfterReveal(revealedNode);
    if (delay <= Duration.zero) {
      _drainQueue();
      return;
    }
    _startRevealTimer(delay);
  }

  void _startRevealTimer(Duration delay) {
    _revealTimer?.cancel();
    _revealTimerStartedAt = DateTime.now();
    _revealTimerDelay = delay;
    _pausedRevealDelay = null;
    _revealTimer = Timer(delay, () {
      _revealTimer = null;
      _revealTimerStartedAt = null;
      _revealTimerDelay = null;
      _drainQueue();
    });
  }

  void _pauseRevealTimer() {
    final Timer? timer = _revealTimer;
    if (timer == null) {
      return;
    }
    timer.cancel();
    _revealTimer = null;
    final DateTime? startedAt = _revealTimerStartedAt;
    final Duration? delay = _revealTimerDelay;
    if (startedAt == null || delay == null) {
      _pausedRevealDelay = Duration.zero;
      return;
    }
    final Duration elapsed = DateTime.now().difference(startedAt);
    final Duration remaining = delay - elapsed;
    _pausedRevealDelay = remaining <= Duration.zero ? Duration.zero : remaining;
    _revealTimerStartedAt = null;
    _revealTimerDelay = null;
  }

  void _resumeRevealTimer() {
    final Duration? remaining = _pausedRevealDelay;
    _pausedRevealDelay = null;
    if (remaining != null && _pendingIds.isNotEmpty) {
      if (remaining <= Duration.zero) {
        _drainQueue();
      } else {
        _startRevealTimer(remaining);
      }
      return;
    }
    _syncSchedule();
  }

  MarkdownRenderNode? _nodeForId(String id) {
    for (final MarkdownRenderNode node in widget.blocks) {
      if (widget.blockIdentityBuilder(node) == id) {
        return node;
      }
    }
    return null;
  }

  void _enterWaiting() {
    if (_isWaiting) {
      return;
    }
    _isWaiting = true;
    widget.onWait?.call();
  }

  @override
  Widget build(BuildContext context) {
    final List<MarkdownRenderNode> visibleBlocks = widget.blocks
        .where(
          (MarkdownRenderNode node) =>
              _visibleIds.contains(widget.blockIdentityBuilder(node)),
        )
        .toList(growable: false);

    if (widget.sliver) {
      return SliverPadding(
        padding: widget.padding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int i) {
              if (i.isOdd) {
                return SizedBox(height: widget.blockSpacing);
              }
              final MarkdownRenderNode node = visibleBlocks[i ~/ 2];
              final String id = widget.blockIdentityBuilder(node);
              return _RevealScheduleScope(
                key: ValueKey<String>('reveal_$id'),
                revealedAt: _revealedAt[id],
                tokenArrivalDelay: widget.tokenArrivalDelay,
                paused: widget.paused,
                child: widget.blockBuilder(context, node),
              );
            },
            childCount:
                visibleBlocks.isEmpty ? 0 : visibleBlocks.length * 2 - 1,
            findChildIndexCallback: (Key key) {
              if (key is! ValueKey<String>) {
                return null;
              }
              final String value = key.value;
              if (!value.startsWith('reveal_')) {
                return null;
              }
              final String id = value.substring('reveal_'.length);
              final int blockIndex = visibleBlocks.indexWhere(
                (MarkdownRenderNode node) =>
                    widget.blockIdentityBuilder(node) == id,
              );
              return blockIndex < 0 ? null : blockIndex * 2;
            },
          ),
        ),
      );
    }

    final List<Widget> blockChildren = <Widget>[
      for (int i = 0; i < visibleBlocks.length; i++) ...[
        _RevealScheduleScope(
          key: ValueKey<String>(
            'reveal_${widget.blockIdentityBuilder(visibleBlocks[i])}',
          ),
          revealedAt:
              _revealedAt[widget.blockIdentityBuilder(visibleBlocks[i])],
          tokenArrivalDelay: widget.tokenArrivalDelay,
          paused: widget.paused,
          child: widget.blockBuilder(context, visibleBlocks[i]),
        ),
        if (i < visibleBlocks.length - 1) SizedBox(height: widget.blockSpacing),
      ],
    ];
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blockChildren,
      ),
    );
  }
}
