part of '../view.dart';

class _VisiblePredecessor {
  const _VisiblePredecessor({required this.id, required this.node});

  final String id;
  final MarkdownRenderNode node;
}

class _SequencedBlockListState extends State<_SequencedBlockList> {
  final Set<String> _visibleIds = <String>{};
  final LinkedHashSet<String> _pendingIds = LinkedHashSet<String>();
  final Map<String, DateTime> _revealedAt = <String, DateTime>{};
  final Map<String, String> _visibleSignatures = <String, String>{};
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
      _resumeRevealTimer();
      _syncSchedule();
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
    _visibleSignatures.removeWhere(
      (String id, String _) => !activeIds.contains(id),
    );

    if (orderedIds.isEmpty) {
      _revealTimer?.cancel();
      _revealTimer = null;
      _revealTimerStartedAt = null;
      _revealTimerDelay = null;
      _pausedRevealDelay = null;
      _pendingIds.clear();
      _visibleSignatures.clear();
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
      if (!widget.paused) {
        _scheduleQueueAfterVisibleTail();
      }
      return;
    }

    if (!widget.paused && _pendingIds.isNotEmpty) {
      _scheduleQueueAfterVisibleTail();
      return;
    }

    if (!widget.paused && _pendingIds.isEmpty && _revealTimer == null) {
      _settleSequence();
    }
  }

  void _drainQueue() {
    if (!mounted || widget.paused) {
      return;
    }
    if (_pendingIds.isEmpty) {
      _settleSequence();
      return;
    }

    final String nextId = _pendingIds.first;
    _pendingIds.remove(nextId);
    final MarkdownRenderNode? revealedNode = _nodeForId(nextId);
    final DateTime revealedAt = DateTime.now();
    setState(() {
      _visibleIds.add(nextId);
      _revealedAt[nextId] = revealedAt;
      if (revealedNode != null) {
        _visibleSignatures[nextId] = _nodeSignature(revealedNode);
      }
    });

    if (_pendingIds.isEmpty) {
      _settleSequence();
      return;
    }

    _scheduleQueueAfterVisibleTail(fallbackNode: revealedNode);
  }

  void _scheduleQueueAfterVisibleTail({MarkdownRenderNode? fallbackNode}) {
    if (!mounted || widget.paused || _pendingIds.isEmpty) {
      return;
    }

    if (fallbackNode != null) {
      final Duration delay = _nextDequeueDelayAfterReveal(fallbackNode);
      if (delay <= Duration.zero) {
        _drainQueue();
      } else {
        _startRevealTimer(delay);
      }
      return;
    }

    final _VisiblePredecessor? predecessor =
        _visiblePredecessorForNextPending();
    final MarkdownRenderNode? node = predecessor?.node;
    if (predecessor == null || node == null) {
      _drainQueue();
      return;
    }

    final String currentSignature = _nodeSignature(node);
    final String? visibleSignature = _visibleSignatures[predecessor.id];
    if (visibleSignature == currentSignature) {
      if (_revealTimer == null) {
        _drainQueue();
      }
      return;
    }

    final Duration delay = _nextDequeueDelayAfterReveal(node);
    if (delay <= Duration.zero) {
      _drainQueue();
      return;
    }
    _visibleSignatures[predecessor.id] = currentSignature;
    if (_revealTimer != null) {
      return;
    }
    _startRevealTimer(delay);
  }

  _VisiblePredecessor? _visiblePredecessorForNextPending() {
    if (_pendingIds.isEmpty) {
      return null;
    }
    final String nextPendingId = _pendingIds.first;
    _VisiblePredecessor? predecessor;
    for (final MarkdownRenderNode node in widget.blocks) {
      final String id = widget.blockIdentityBuilder(node);
      if (id == nextPendingId) {
        return predecessor;
      }
      if (_visibleIds.contains(id)) {
        predecessor = _VisiblePredecessor(id: id, node: node);
      }
    }
    return predecessor;
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

  String _nodeSignature(MarkdownRenderNode node) {
    return '${node.type}\n${node.raw}\n${node.content}';
  }

  void _enterWaiting() {
    if (_isWaiting) {
      return;
    }
    _isWaiting = true;
    widget.onWait?.call();
  }

  void _settleSequence() {
    if (_isWaiting) {
      return;
    }
    widget.onSequenceSettled?.call();
    _enterWaiting();
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
