part of '../view.dart';

/// Hosts selection for a sliver [AnimatedStreamingMarkdown].
///
/// Put this widget around the [CustomScrollView] that contains the Markdown
/// sliver. A host intentionally accepts one Markdown renderer so offsets remain
/// relative to one source snapshot.
class AnimatedStreamingMarkdownSelectionArea extends StatefulWidget {
  /// Creates a source-selection coordinator around a sliver scroll view.
  const AnimatedStreamingMarkdownSelectionArea({
    super.key,
    this.controller,
    this.scrollPadding = const EdgeInsets.all(20),
    required this.child,
  });

  /// Controller shared with the single Markdown sliver inside [child].
  ///
  /// The area owns an internal controller when this is null.
  final AnimatedMarkdownSelectionController? controller;

  /// Padding kept around keyboard or programmatically revealed endpoints.
  final EdgeInsets scrollPadding;

  /// Scroll view containing exactly one selectable Markdown renderer.
  final Widget child;

  @override
  State<AnimatedStreamingMarkdownSelectionArea> createState() =>
      _AnimatedStreamingMarkdownSelectionAreaState();
}

class _AnimatedStreamingMarkdownSelectionAreaState
    extends State<AnimatedStreamingMarkdownSelectionArea> {
  late _MarkdownSelectionHost _host = _createHost();

  _MarkdownSelectionHost _createHost() {
    return _MarkdownSelectionHost(
      controller: widget.controller,
      scrollPadding: widget.scrollPadding,
    );
  }

  @override
  void didUpdateWidget(
    covariant AnimatedStreamingMarkdownSelectionArea oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final _MarkdownSelectionHost oldHost = _host;
      _host = _createHost();
      oldHost.dispose();
      return;
    }
    _host.scrollPadding = widget.scrollPadding;
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MarkdownSelectionArea(
      host: _host,
      child: widget.child,
    );
  }
}

enum _MarkdownSelectionPhase { idle, dragging, leased, finalized }

class _MarkdownSelectionDocument {
  const _MarkdownSelectionDocument({
    required this.projection,
    required this.blockRanges,
    required this.selectionStrategy,
    required this.allowUnclosedInlineDelimiters,
    required this.selectionColor,
  });

  final _MarkdownSelectionProjection projection;
  final Map<String, _MarkdownSelectionBlockRange> blockRanges;
  final SelectionStrategy selectionStrategy;
  final bool allowUnclosedInlineDelimiters;
  final Color selectionColor;

  String get sourceText => projection.fullMarkdownText;
}

class _MarkdownSelectionHost extends ChangeNotifier {
  static const double _selectionScrollVelocityScalar = 30;
  static const double _selectionDragTargetExtent = 40;

  _MarkdownSelectionHost({
    AnimatedMarkdownSelectionController? controller,
    required EdgeInsets scrollPadding,
  })  : controller = controller ?? AnimatedMarkdownSelectionController(),
        _ownsController = controller == null,
        _scrollPadding = scrollPadding;

  final AnimatedMarkdownSelectionController controller;
  final bool _ownsController;

  _MarkdownSelectionDocument? _document;
  _MarkdownSelectionDocument? get document => _document;

  EdgeInsets get scrollPadding => _scrollPadding;
  EdgeInsets _scrollPadding;
  set scrollPadding(EdgeInsets value) {
    if (_scrollPadding == value) {
      return;
    }
    _scrollPadding = value;
    notifyListeners();
  }

  _MarkdownSelectionPhase phase = _MarkdownSelectionPhase.idle;
  final Set<String> leasedBlockIdentities = <String>{};
  Object? _rendererOwner;
  bool _notificationScheduled = false;
  TextSelection? _visualSourceSelection;
  TextSelection? _visualDisplaySelection;
  TextSelection? _endpointAnchorSelection;
  _MarkdownSelectionEndpointAnchor? _baseEndpointAnchor;
  _MarkdownSelectionEndpointAnchor? _extentEndpointAnchor;
  bool synchronizingSourceText = false;
  final Map<Object, _MarkdownSelectionScrollTarget> _scrollTargets =
      <Object, _MarkdownSelectionScrollTarget>{};
  VoidCallback? autoScrollFrameCallback;
  int _autoScrollGeneration = 0;
  bool _disposed = false;

  bool get isAutoScrolling => _scrollTargets.values.any(
        (_MarkdownSelectionScrollTarget target) => target.scroller.scrolling,
      );

  ScrollPosition? get primaryVerticalScrollPosition {
    for (final _MarkdownSelectionScrollTarget target in _scrollTargets.values) {
      if (target.scrollable.mounted &&
          axisDirectionToAxis(target.scrollable.axisDirection) ==
              Axis.vertical) {
        return target.scrollable.position;
      }
    }
    return null;
  }

  void registerScrollable(Object owner, ScrollableState scrollable) {
    final _MarkdownSelectionScrollTarget? current = _scrollTargets[owner];
    if (current?.scrollable == scrollable) {
      return;
    }
    current?.scroller.stopAutoScroll();
    _scrollTargets[owner] = _MarkdownSelectionScrollTarget(
      scrollable: scrollable,
      scroller: EdgeDraggingAutoScroller(
        scrollable,
        velocityScalar: _selectionScrollVelocityScalar,
        onScrollViewScrolled: () {
          autoScrollFrameCallback?.call();
        },
      ),
    );
  }

  void unregisterScrollable(Object owner) {
    _scrollTargets.remove(owner)?.scroller.stopAutoScroll();
  }

  void startAutoScroll(Offset globalPosition, Set<Axis> axisIntent) {
    for (final _MarkdownSelectionScrollTarget target in _scrollTargets.values) {
      final RenderObject? object = target.scrollable.context.findRenderObject();
      if (object is! RenderBox || !object.hasSize) {
        continue;
      }
      final Rect viewport = object.localToGlobal(Offset.zero) & object.size;
      final Axis axis = axisDirectionToAxis(target.scrollable.axisDirection);
      if (!axisIntent.contains(axis)) {
        continue;
      }
      if (axis == Axis.horizontal &&
          (globalPosition.dy < viewport.top ||
              globalPosition.dy > viewport.bottom)) {
        continue;
      }
      if (axis == Axis.vertical &&
          (globalPosition.dx < viewport.left ||
              globalPosition.dx > viewport.right)) {
        continue;
      }
      target.scroller.startAutoScrollIfNecessary(
        Rect.fromCenter(
          center: globalPosition,
          width: _selectionDragTargetExtent,
          height: _selectionDragTargetExtent,
        ),
      );
    }
  }

  void stopAutoScroll({bool cancelScrollActivity = true}) {
    final int generation = ++_autoScrollGeneration;
    _stopRegisteredScrollActivities(
      cancelScrollActivity: cancelScrollActivity,
      forceCancel: false,
    );
    if (!cancelScrollActivity || _disposed) {
      return;
    }
    // Pointer routing and SelectableRegion's gesture recognizers finish in
    // the same event cycle, but not necessarily in the same order. A native
    // scrollable selection delegate can therefore start its final animateTo
    // after the pointer listener above has already cancelled our scroller.
    // Cancel once more after that event cycle, before a second scroll frame is
    // allowed to run. A new drag invalidates this callback in [beginDrag].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          generation != _autoScrollGeneration ||
          phase == _MarkdownSelectionPhase.dragging ||
          phase == _MarkdownSelectionPhase.leased) {
        return;
      }
      _stopRegisteredScrollActivities(
        cancelScrollActivity: true,
        forceCancel: true,
      );
    });
  }

  void _stopRegisteredScrollActivities({
    required bool cancelScrollActivity,
    required bool forceCancel,
  }) {
    final Set<ScrollPosition> cancelledPositions = <ScrollPosition>{};
    for (final _MarkdownSelectionScrollTarget target in _scrollTargets.values) {
      final bool wasScrolling = target.scroller.scrolling;
      target.scroller.stopAutoScroll();
      if (!cancelScrollActivity || !target.scrollable.mounted) {
        continue;
      }
      final ScrollPosition position = target.scrollable.position;
      if ((wasScrolling || forceCancel) &&
          cancelledPositions.add(position) &&
          position.hasPixels &&
          position.hasContentDimensions) {
        position.jumpTo(
          position.pixels.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    }
  }

  bool attachRenderer(
    Object owner,
    _MarkdownSelectionDocument document, {
    AnimatedMarkdownSelectionController? rendererController,
  }) {
    assert(
      _rendererOwner == null || identical(_rendererOwner, owner),
      'AnimatedStreamingMarkdownSelectionArea manages exactly one '
      'AnimatedStreamingMarkdown renderer.',
    );
    if (_rendererOwner != null && !identical(_rendererOwner, owner)) {
      return false;
    }
    assert(
      rendererController == null || identical(rendererController, controller),
      'The sliver renderer and AnimatedStreamingMarkdownSelectionArea must '
      'use the same selectionController.',
    );
    if (rendererController != null &&
        !identical(rendererController, controller)) {
      return false;
    }
    _rendererOwner = owner;
    _setDocument(document);
    return true;
  }

  void detachRenderer(Object owner) {
    if (!identical(_rendererOwner, owner)) {
      return;
    }
    _rendererOwner = null;
  }

  void updateBoxDocument(_MarkdownSelectionDocument document) {
    _setDocument(document);
  }

  void _setDocument(_MarkdownSelectionDocument next) {
    final _MarkdownSelectionDocument? previous = _document;
    if (previous != null &&
        previous.sourceText == next.sourceText &&
        previous.selectionStrategy == next.selectionStrategy &&
        previous.allowUnclosedInlineDelimiters ==
            next.allowUnclosedInlineDelimiters &&
        previous.selectionColor == next.selectionColor) {
      _document = next;
      return;
    }
    if (previous != null && _endpointAnchorSelection != controller.selection) {
      _captureEndpointAnchors(previous, controller.selection);
    }
    final TextSelection remapped = previous == null
        ? controller.selection
        : _remapSelection(previous, next, controller.selection);
    _document = next;
    if (phase == _MarkdownSelectionPhase.dragging) {
      phase = _MarkdownSelectionPhase.leased;
    }
    if (previous != null && !next.sourceText.startsWith(previous.sourceText)) {
      clearVisualSelection();
    }
    synchronizingSourceText = true;
    try {
      controller._synchronizeSourceText(
        next.sourceText,
        remappedSelection: remapped,
      );
    } finally {
      synchronizingSourceText = false;
    }
    _endpointAnchorSelection = remapped;
    _scheduleNotification();
  }

  void setVisualSelection({
    required TextSelection sourceSelection,
    required TextSelection displaySelection,
  }) {
    _visualSourceSelection = sourceSelection;
    _visualDisplaySelection = displaySelection;
    final _MarkdownSelectionDocument? activeDocument = _document;
    if (activeDocument != null && _endpointAnchorSelection != sourceSelection) {
      _captureEndpointAnchors(activeDocument, sourceSelection);
    }
  }

  TextSelection? visualSelectionFor(TextSelection sourceSelection) {
    return _visualSourceSelection == sourceSelection
        ? _visualDisplaySelection
        : null;
  }

  void clearVisualSelection() {
    _visualSourceSelection = null;
    _visualDisplaySelection = null;
  }

  void clearEndpointAnchors() {
    _baseEndpointAnchor = null;
    _extentEndpointAnchor = null;
    _endpointAnchorSelection = null;
  }

  void _captureEndpointAnchors(
    _MarkdownSelectionDocument document,
    TextSelection selection,
  ) {
    if (!selection.isValid) {
      clearEndpointAnchors();
      return;
    }
    _baseEndpointAnchor = _endpointAnchorFor(
      document,
      selection.baseOffset,
      preferNextAtBoundary: true,
    );
    _extentEndpointAnchor = _endpointAnchorFor(
      document,
      selection.extentOffset,
      preferNextAtBoundary: false,
    );
    _endpointAnchorSelection = selection;
  }

  _MarkdownSelectionEndpointAnchor? _endpointAnchorFor(
    _MarkdownSelectionDocument document,
    int sourceOffset, {
    required bool preferNextAtBoundary,
  }) {
    for (final MapEntry<String, _MarkdownSelectionBlockRange> entry
        in document.blockRanges.entries) {
      final _MarkdownSelectionBlockRange block = entry.value;
      if (sourceOffset < block.sourceRange.start ||
          sourceOffset > block.sourceRange.end) {
        continue;
      }
      final int plainOffset = document.projection.plainOffsetForSourceOffset(
        sourceOffset,
        preferNextAtBoundary: preferNextAtBoundary,
      );
      return _MarkdownSelectionEndpointAnchor(
        blockIdentity: entry.key,
        localSemanticOffset: plainOffset - block.plainRange.start,
        fallbackSourceOffset: sourceOffset,
      );
    }
    return null;
  }

  int? _sourceOffsetForEndpointAnchor(
    _MarkdownSelectionDocument document,
    _MarkdownSelectionEndpointAnchor? anchor, {
    required bool preferNextAtBoundary,
  }) {
    if (anchor == null) {
      return null;
    }
    final _MarkdownSelectionBlockRange? block =
        document.blockRanges[anchor.blockIdentity];
    if (block == null) {
      return null;
    }
    final int localOffset = anchor.localSemanticOffset.clamp(
      0,
      block.plainRange.end - block.plainRange.start,
    );
    return document.projection.sourceOffsetForPlainOffset(
      block.plainRange.start + localOffset,
      preferNextAtBoundary: preferNextAtBoundary,
    );
  }

  TextSelection _remapSelection(
    _MarkdownSelectionDocument previous,
    _MarkdownSelectionDocument next,
    TextSelection selection,
  ) {
    if (!selection.isValid) {
      return selection;
    }
    final bool baseAnchorRemounted = _endpointAnchorRemounted(
      previous,
      next,
      _baseEndpointAnchor,
    );
    final bool extentAnchorRemounted = _endpointAnchorRemounted(
      previous,
      next,
      _extentEndpointAnchor,
    );
    if (next.sourceText.startsWith(previous.sourceText) &&
        !baseAnchorRemounted &&
        !extentAnchorRemounted) {
      return selection;
    }
    return TextSelection(
      baseOffset: _sourceOffsetForEndpointAnchor(
            next,
            _baseEndpointAnchor,
            preferNextAtBoundary: true,
          ) ??
          _remapEndpoint(
            previous,
            next,
            selection.baseOffset,
            preferNextAtBoundary: true,
          ),
      extentOffset: _sourceOffsetForEndpointAnchor(
            next,
            _extentEndpointAnchor,
            preferNextAtBoundary: false,
          ) ??
          _remapEndpoint(
            previous,
            next,
            selection.extentOffset,
            preferNextAtBoundary: false,
          ),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  bool _endpointAnchorRemounted(
    _MarkdownSelectionDocument previous,
    _MarkdownSelectionDocument next,
    _MarkdownSelectionEndpointAnchor? anchor,
  ) {
    if (anchor == null) {
      return false;
    }
    return !previous.blockRanges.containsKey(anchor.blockIdentity) &&
        next.blockRanges.containsKey(anchor.blockIdentity);
  }

  int _remapEndpoint(
    _MarkdownSelectionDocument previous,
    _MarkdownSelectionDocument next,
    int sourceOffset, {
    required bool preferNextAtBoundary,
  }) {
    String? identity;
    _MarkdownSelectionBlockRange? oldBlock;
    for (final MapEntry<String, _MarkdownSelectionBlockRange> entry
        in previous.blockRanges.entries) {
      final _MarkdownSourceSelectionRange range = entry.value.sourceRange;
      if (sourceOffset >= range.start && sourceOffset <= range.end) {
        identity = entry.key;
        oldBlock = entry.value;
        break;
      }
    }
    final _MarkdownSelectionBlockRange? newBlock =
        identity == null ? null : next.blockRanges[identity];
    if (oldBlock != null && newBlock != null) {
      final int oldPlainOffset = previous.projection.plainOffsetForSourceOffset(
        sourceOffset,
        preferNextAtBoundary: preferNextAtBoundary,
      );
      final int localSemanticOffset =
          oldPlainOffset - oldBlock.plainRange.start;
      final int newPlainOffset = newBlock.plainRange.start +
          localSemanticOffset.clamp(
            0,
            newBlock.plainRange.end - newBlock.plainRange.start,
          );
      return next.projection.sourceOffsetForPlainOffset(
        newPlainOffset,
        preferNextAtBoundary: preferNextAtBoundary,
      );
    }
    return AnimatedMarkdownSelectionController._nearestGraphemeBoundary(
      next.sourceText,
      sourceOffset.clamp(0, next.sourceText.length),
    );
  }

  void beginDrag() {
    _autoScrollGeneration += 1;
    leasedBlockIdentities.clear();
    phase = _MarkdownSelectionPhase.dragging;
  }

  void leaseGeometryAtDisplayOffset(int offset) {
    final _MarkdownSelectionDocument? activeDocument = _document;
    if (activeDocument == null) {
      return;
    }
    for (final MapEntry<String, _MarkdownSelectionBlockRange> entry
        in activeDocument.blockRanges.entries) {
      final _MarkdownSelectionRange range = entry.value.plainRange;
      if (offset >= range.start && offset <= range.end) {
        leasedBlockIdentities.add(entry.key);
        break;
      }
    }
  }

  bool shouldLeaseBlock(String identity) {
    return phase == _MarkdownSelectionPhase.leased &&
        leasedBlockIdentities.contains(identity);
  }

  void finalize() {
    if (phase != _MarkdownSelectionPhase.finalized) {
      phase = _MarkdownSelectionPhase.finalized;
      notifyListeners();
    }
    leasedBlockIdentities.clear();
  }

  void clearPhase() {
    if (phase != _MarkdownSelectionPhase.idle) {
      phase = _MarkdownSelectionPhase.idle;
      leasedBlockIdentities.clear();
      clearVisualSelection();
      clearEndpointAnchors();
      notifyListeners();
    }
  }

  void _scheduleNotification() {
    if (_notificationScheduled) {
      return;
    }
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    stopAutoScroll(cancelScrollActivity: false);
    _scrollTargets.clear();
    autoScrollFrameCallback = null;
    if (_ownsController) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _MarkdownSelectionScrollTarget {
  const _MarkdownSelectionScrollTarget({
    required this.scrollable,
    required this.scroller,
  });

  final ScrollableState scrollable;
  final EdgeDraggingAutoScroller scroller;
}

class _MarkdownSelectionEndpointAnchor {
  const _MarkdownSelectionEndpointAnchor({
    required this.blockIdentity,
    required this.localSemanticOffset,
    required this.fallbackSourceOffset,
  });

  final String blockIdentity;
  final int localSemanticOffset;
  final int fallbackSourceOffset;
}

class _MarkdownSelectionHostScope extends InheritedWidget {
  const _MarkdownSelectionHostScope({
    required this.host,
    required super.child,
  });

  final _MarkdownSelectionHost host;

  static _MarkdownSelectionHost? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_MarkdownSelectionHostScope>()
        ?.host;
  }

  @override
  bool updateShouldNotify(_MarkdownSelectionHostScope oldWidget) {
    return host != oldWidget.host;
  }
}

class _MarkdownSelectionDocumentRegistration extends StatefulWidget {
  const _MarkdownSelectionDocumentRegistration({
    required this.host,
    required this.document,
    required this.rendererController,
    required this.child,
  });

  final _MarkdownSelectionHost host;
  final _MarkdownSelectionDocument document;
  final AnimatedMarkdownSelectionController? rendererController;
  final Widget child;

  @override
  State<_MarkdownSelectionDocumentRegistration> createState() =>
      _MarkdownSelectionDocumentRegistrationState();
}

class _MarkdownSelectionDocumentRegistrationState
    extends State<_MarkdownSelectionDocumentRegistration> {
  final Object _owner = Object();
  final Object _scrollOwner = Object();
  bool _attached = false;
  ScrollableState? _scrollable;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(
    covariant _MarkdownSelectionDocumentRegistration oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      oldWidget.host.detachRenderer(_owner);
      oldWidget.host.unregisterScrollable(_scrollOwner);
    }
    _attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ScrollableState? next = Scrollable.maybeOf(context);
    if (next == _scrollable) {
      return;
    }
    widget.host.unregisterScrollable(_scrollOwner);
    _scrollable = next;
    if (next != null) {
      widget.host.registerScrollable(_scrollOwner, next);
    }
  }

  void _attach() {
    _attached = widget.host.attachRenderer(
      _owner,
      widget.document,
      rendererController: widget.rendererController,
    );
  }

  @override
  void dispose() {
    widget.host.detachRenderer(_owner);
    widget.host.unregisterScrollable(_scrollOwner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _attached
        ? widget.child
        : SelectionContainer.disabled(child: widget.child);
  }
}

class _MarkdownSelectionScrollableRegistration extends StatefulWidget {
  const _MarkdownSelectionScrollableRegistration({required this.child});

  final Widget child;

  @override
  State<_MarkdownSelectionScrollableRegistration> createState() =>
      _MarkdownSelectionScrollableRegistrationState();
}

class _MarkdownSelectionScrollableRegistrationState
    extends State<_MarkdownSelectionScrollableRegistration> {
  final Object _scrollOwner = Object();
  _MarkdownSelectionHost? _host;
  ScrollableState? _scrollable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final _MarkdownSelectionHost? nextHost =
        _MarkdownSelectionHostScope.maybeOf(context);
    final ScrollableState? nextScrollable = Scrollable.maybeOf(context);
    if (nextHost == _host && nextScrollable == _scrollable) {
      return;
    }
    _host?.unregisterScrollable(_scrollOwner);
    _host = nextHost;
    _scrollable = nextScrollable;
    if (nextHost != null && nextScrollable != null) {
      nextHost.registerScrollable(_scrollOwner, nextScrollable);
    }
  }

  @override
  void dispose() {
    _host?.unregisterScrollable(_scrollOwner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MarkdownSelectionArea extends StatefulWidget {
  const _MarkdownSelectionArea({
    this.document,
    this.host,
    this.selectionController,
    this.scrollPadding = const EdgeInsets.all(20),
    required this.child,
  }) : assert((document == null) != (host == null));

  final _MarkdownSelectionDocument? document;
  final _MarkdownSelectionHost? host;
  final AnimatedMarkdownSelectionController? selectionController;
  final EdgeInsets scrollPadding;
  final Widget child;

  @override
  State<_MarkdownSelectionArea> createState() => _MarkdownSelectionAreaState();
}

class _MarkdownSelectionAreaState extends State<_MarkdownSelectionArea> {
  final GlobalKey<State<StatefulWidget>> _selectionAreaKey =
      GlobalKey<State<StatefulWidget>>();
  final _MarkdownInlineSelectionRegistry _inlineSelectionRegistry =
      _MarkdownInlineSelectionRegistry();
  SelectedContent? _selectedContent;
  _MarkdownSelectionRange? _selectionRange;
  _MarkdownSelectionRange? _selectionCompactRange;
  _MarkdownSourceSelectionRange? _sourceSelectionRange;
  _MarkdownSelectionDragAnchor? _selectionDragAnchor;
  String _lastSelectedPlainText = '';
  bool _selectionRangeLocked = false;
  bool _suppressFrameworkSelectionClear = false;
  bool _sourceSelectionVisualActive = false;
  bool _frameworkSelectionClearScheduled = false;
  bool _selectionPointerActive = false;
  bool _selectionCreatedByPointer = false;
  bool _deferViewportFreezeUntilPointerUp = false;
  bool _frameworkSelectionChanging = false;
  bool _ignoreFrameworkDragUpdatesUntilFinalized = false;
  bool _selectionReleasePendingFinalize = false;
  int _selectionReleaseGuardEpoch = 0;
  bool _hasPointerHitTestDragUpdate = false;
  bool _selectionPointerMoved = false;
  bool _discretePointerSelection = false;
  bool _plainClickDismissalPending = false;
  final Set<int> _inAppPrimaryPointers = <int>{};
  int _pointerInteractionEpoch = 0;
  int? _activeSelectionPointer;
  int _selectionEpoch = 0;
  ScrollPosition? _scrollPosition;
  ScrollableState? _scrollableState;
  final Object _scrollOwner = Object();
  double? _lastScrollPixels;
  Offset? _lastSelectionDragGlobalPosition;
  Offset? _selectionDragOriginGlobalPosition;
  Set<Axis> _selectionDragAxisIntent = const <Axis>{};
  late final FocusNode _focusNode = FocusNode(debugLabel: 'markdown-selection');
  late _MarkdownSelectionHost _host;
  late bool _ownsHost;
  bool _updatingController = false;
  bool _controllerSyncScheduled = false;
  bool _finalizedGeometrySyncScheduled = false;

  _MarkdownSelectionDocument? get _document => _host.document;
  _MarkdownSelectionProjection? get _projection => _document?.projection;
  SelectionStrategy get _selectionStrategy =>
      _document?.selectionStrategy ?? SelectionStrategy.rich;
  bool get _allowUnclosedInlineDelimiters =>
      _document?.allowUnclosedInlineDelimiters ?? false;
  Color get _selectionColor =>
      _document?.selectionColor ?? const Color(0x6658A6FF);
  bool get _useSourceSelectionVisual => true;
  bool get _selectionInteractionActive =>
      _selectionPointerActive || _frameworkSelectionChanging;

  @override
  void initState() {
    super.initState();
    _installHost();
    _focusNode.addListener(_handleFocusChanged);
    _inlineSelectionRegistry.addListener(_handleInlineSelectionChanged);
    _inlineSelectionRegistry.addDragUpdateListener(
      _handleInlineSelectionDragUpdate,
    );
    _inlineSelectionRegistry.onDiscreteSelection =
        _handleDiscretePointerSelection;
    _inlineSelectionRegistry.shouldReturnPending = () =>
        _selectionReleasePendingFinalize ||
        (_selectionPointerActive && _lastSelectionDragGlobalPosition != null);
    _inlineSelectionRegistry.shouldIgnoreFrameworkEdgeUpdate = () =>
        (_selectionPointerActive &&
            !_selectionPointerMoved &&
            !_discretePointerSelection) ||
        _plainClickDismissalPending;
    web_copy.WebCopyInterceptor.attach(
      focusNode: _focusNode,
      onCopy: _handleBrowserCopy,
    );
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _applyControllerSelection(reveal: false);
  }

  void _installHost() {
    _ownsHost = widget.host == null;
    _host = widget.host ??
        _MarkdownSelectionHost(
          controller: widget.selectionController,
          scrollPadding: widget.scrollPadding,
        );
    _host.addListener(_handleHostChanged);
    _host.controller.addListener(_handleControllerChanged);
    _host.autoScrollFrameCallback = _handleSelectionAutoScrollFrame;
    final _MarkdownSelectionDocument? document = widget.document;
    if (_ownsHost && document != null) {
      _host.updateBoxDocument(document);
    }
  }

  void _uninstallHost() {
    _host.unregisterScrollable(_scrollOwner);
    if (_host.autoScrollFrameCallback == _handleSelectionAutoScrollFrame) {
      _host.autoScrollFrameCallback = null;
    }
    _host.controller.removeListener(_handleControllerChanged);
    _host.removeListener(_handleHostChanged);
    if (_ownsHost) {
      _host.dispose();
    }
  }

  @override
  void dispose() {
    _selectionReleaseGuardEpoch += 1;
    _selectionReleasePendingFinalize = false;
    _stopSelectionAutoScroll(
      clearDragPosition: true,
      cancelScrollActivity: false,
    );
    web_copy.WebCopyInterceptor.detach(focusNode: _focusNode);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _detachScrollPosition();
    _inlineSelectionRegistry.removeDragUpdateListener(
      _handleInlineSelectionDragUpdate,
    );
    _inlineSelectionRegistry.onDiscreteSelection = null;
    _inlineSelectionRegistry.shouldIgnoreFrameworkEdgeUpdate = null;
    _inlineSelectionRegistry.removeListener(_handleInlineSelectionChanged);
    _inlineSelectionRegistry.dispose();
    _inAppPrimaryPointers.clear();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _uninstallHost();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ScrollableState? nextScrollable = Scrollable.maybeOf(context);
    final ScrollPosition? nextScrollPosition = nextScrollable?.position;
    if (nextScrollPosition == _scrollPosition &&
        nextScrollable == _scrollableState) {
      return;
    }
    _detachScrollPosition();
    _scrollableState = nextScrollable;
    _scrollPosition = nextScrollPosition;
    if (nextScrollable != null) {
      _host.registerScrollable(_scrollOwner, nextScrollable);
    }
    _lastScrollPixels = nextScrollPosition?.pixels;
    nextScrollPosition?.isScrollingNotifier.addListener(_handleScrollActivity);
    nextScrollPosition?.addListener(_handleScrollOffsetChanged);
  }

  @override
  void didUpdateWidget(covariant _MarkdownSelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool hostChanged = oldWidget.host != widget.host ||
        (widget.host == null &&
            oldWidget.selectionController != widget.selectionController);
    if (hostChanged) {
      _uninstallHost();
      _installHost();
      _applyControllerSelection(reveal: false);
    } else if (_ownsHost) {
      _host.scrollPadding = widget.scrollPadding;
      final _MarkdownSelectionDocument? document = widget.document;
      if (document != null) {
        _host.updateBoxDocument(document);
      }
    }
    final _MarkdownSelectionProjection? projection = _projection;
    final _MarkdownSelectionRange? currentRange = _selectionRange;
    if (currentRange == null || projection == null) {
      return;
    }
    final int max = projection.fullPlainText.length;
    final int start = currentRange.start.clamp(0, max);
    final int end = currentRange.end.clamp(start, max);
    _selectionRange = _MarkdownSelectionRange(start: start, end: end);
    final _MarkdownSelectionRange? compactRange = _selectionCompactRange;
    if (compactRange != null) {
      final int compactMax = projection.compactPlainText.length;
      final int compactStart = compactRange.start.clamp(0, compactMax);
      final int compactEnd = compactRange.end.clamp(compactStart, compactMax);
      _selectionCompactRange = _MarkdownSelectionRange(
        start: compactStart,
        end: compactEnd,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _MarkdownSelectionHostScope(
      host: _host,
      child: Actions(
        actions: <Type, Action<Intent>>{
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (CopySelectionTextIntent intent) {
              _copyMarkdownSelection();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          canRequestFocus: true,
          child: Listener(
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerFinished,
            onPointerCancel: _handlePointerFinished,
            child: SelectionArea(
              key: _selectionAreaKey,
              contextMenuBuilder: (
                BuildContext context,
                SelectableRegionState selectableRegionState,
              ) {
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: selectableRegionState.contextMenuAnchors,
                  buttonItems: selectableRegionState.contextMenuButtonItems
                      .map((ContextMenuButtonItem item) {
                    if (item.type != ContextMenuButtonType.copy) {
                      return item;
                    }
                    return ContextMenuButtonItem(
                      type: item.type,
                      label: item.label,
                      onPressed: () {
                        _copyMarkdownSelection();
                        selectableRegionState.hideToolbar();
                      },
                    );
                  }).toList(growable: false),
                );
              },
              onSelectionChanged: (SelectedContent? content) {
                _selectedContent = content;
                if (_plainClickDismissalPending &&
                    (content?.plainText.isNotEmpty ?? false)) {
                  _selectedContent = null;
                  _clearFrameworkSelectionVisual();
                  _inlineSelectionRegistry.applyDisplaySelection(null);
                  return;
                }
                if (_selectionPointerActive && _hasPointerHitTestDragUpdate) {
                  return;
                }
                final String plainText = content?.plainText ?? '';
                if (plainText.isEmpty) {
                  if (_suppressFrameworkSelectionClear) {
                    _suppressFrameworkSelectionClear = false;
                    return;
                  }
                  if (_selectionRangeLocked && _sourceSelectionRange != null) {
                    return;
                  }
                  if (!_focusNode.hasFocus) {
                    if ((_inAppPrimaryPointers.isNotEmpty &&
                            _focusMovedWithinApplication) ||
                        !_host.controller.value.hasSelection) {
                      _clearSelectionCache();
                    } else {
                      _preserveSelectionAfterExternalFocusLoss();
                    }
                  }
                  return;
                }
                if (_host.phase == _MarkdownSelectionPhase.finalized &&
                    _host.controller.value.hasSelection &&
                    !_selectionPointerActive &&
                    !_frameworkSelectionChanging) {
                  // Sliver/viewport churn can temporarily report only the
                  // mounted subset. The controller remains authoritative after
                  // finalization, just like TextEditingController.
                  return;
                }
                if (_selectionRangeLocked) {
                  if (_selectionPointerActive &&
                      _deferViewportFreezeUntilPointerUp) {
                    _clearFrameworkSelectionVisual();
                    return;
                  }
                  if (_selectionPointerActive) {
                    _clearSelectionCache(
                      notify: _sourceSelectionVisualActive,
                    );
                  } else {
                    _clearFrameworkSelectionVisual();
                    return;
                  }
                }
                _selectionCreatedByPointer =
                    _selectionCreatedByPointer || _selectionPointerActive;
                _syncSelectionFromFramework(plainText);
                if (content != null && !_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                }
              },
              child: _MarkdownInlineSelectionRegistryScope(
                registry: _inlineSelectionRegistry,
                child: _MarkdownSourceSelectionVisualScope(
                  sourceRange: _sourceSelectionVisualActive
                      ? _sourceSelectionRange
                      : null,
                  plainRange:
                      _sourceSelectionVisualActive ? _selectionRange : null,
                  selectionColor: _selectionColor,
                  child: _SelectableRegionStatusListener(
                    onStatusChanged: _handleSelectableRegionStatusChanged,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleHostChanged() {
    _scheduleControllerSync(reveal: false);
  }

  void _handleControllerChanged() {
    if (_updatingController) {
      return;
    }
    final bool synchronizingSourceText = _host.synchronizingSourceText;
    if (!synchronizingSourceText) {
      _host.clearVisualSelection();
      _host.clearEndpointAnchors();
    }
    _scheduleControllerSync(reveal: !synchronizingSourceText);
  }

  void _scheduleControllerSync({required bool reveal}) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _applyControllerSelection(reveal: reveal);
      return;
    }
    if (_controllerSyncScheduled) {
      return;
    }
    _controllerSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controllerSyncScheduled = false;
      if (mounted) {
        _applyControllerSelection(reveal: reveal);
      }
    });
  }

  void _applyControllerSelection({required bool reveal}) {
    final _MarkdownSelectionProjection? projection = _projection;
    if (projection == null) {
      return;
    }
    final TextSelection sourceSelection = _host.controller.selection;
    if (!sourceSelection.isValid || sourceSelection.isCollapsed) {
      _inlineSelectionRegistry.applyDisplaySelection(null);
      final bool needsRebuild = _sourceSelectionVisualActive;
      void clear() {
        _selectionRange = null;
        _selectionCompactRange = null;
        _sourceSelectionRange = null;
        _lastSelectedPlainText = '';
        _sourceSelectionVisualActive = false;
      }

      if (needsRebuild && mounted) {
        setState(clear);
      } else {
        clear();
      }
      return;
    }
    final TextSelection displaySelection =
        _host.visualSelectionFor(sourceSelection) ??
            projection.plainSelectionForSourceSelection(sourceSelection);
    _host.setVisualSelection(
      sourceSelection: sourceSelection,
      displaySelection: displaySelection,
    );
    final TextSelection compactSelection =
        projection.plainSelectionForSourceSelection(
      sourceSelection,
      plainSeparator: '',
    );
    final _MarkdownSelectionRange displayRange = _MarkdownSelectionRange(
      start: displaySelection.start,
      end: displaySelection.end,
    );
    final _MarkdownSelectionRange compactRange = _MarkdownSelectionRange(
      start: compactSelection.start,
      end: compactSelection.end,
    );
    final _MarkdownSourceSelectionRange sourceRange =
        _MarkdownSourceSelectionRange(
      start: sourceSelection.start,
      end: sourceSelection.end,
    );
    _inlineSelectionRegistry.applyDisplaySelection(displaySelection);
    final bool visualActive = _useSourceSelectionVisual &&
        (!_selectionInteractionActive || _selectionRangeLocked);
    final bool visualChanged = _sourceSelectionVisualActive != visualActive ||
        _selectionRange != displayRange ||
        _sourceSelectionRange != sourceRange;

    void apply() {
      _selectionRange = displayRange;
      _selectionCompactRange = compactRange;
      _sourceSelectionRange = sourceRange;
      _lastSelectedPlainText = projection.plainTextForRange(displayRange);
      _sourceSelectionVisualActive = visualActive;
    }

    if (visualChanged && mounted) {
      setState(apply);
    } else {
      apply();
    }
    if (reveal) {
      _scheduleRevealSelectionEndpoint(sourceSelection.extentOffset);
    }
  }

  void _updateControllerSelection(
    TextSelection selection, {
    TextSelection? displaySelection,
  }) {
    final _MarkdownSelectionDocument? document = _document;
    if (document == null) {
      return;
    }
    _updatingController = true;
    try {
      if (displaySelection != null) {
        _host.setVisualSelection(
          sourceSelection: selection,
          displaySelection: displaySelection,
        );
      } else if (!selection.isValid || selection.isCollapsed) {
        _host.clearVisualSelection();
      }
      _host.controller._updateFromRenderer(
        sourceText: document.sourceText,
        selection: selection,
      );
    } finally {
      _updatingController = false;
    }
  }

  void _scheduleRevealSelectionEndpoint(int sourceOffset, {int attempt = 0}) {
    final _MarkdownSelectionProjection? projection = _projection;
    if (projection == null || sourceOffset < 0) {
      return;
    }
    final int displayOffset = projection.plainOffsetForSourceOffset(
      sourceOffset,
      preferNextAtBoundary: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final _RenderSelectableInlineTextProxy? selectable =
          _inlineSelectionRegistry.selectableForDisplayOffset(
        displayOffset,
        allowClosest: false,
      );
      if (selectable != null) {
        final Rect caret = selectable.caretRectForDisplayOffset(displayOffset);
        final EdgeInsets padding = _host.scrollPadding;
        selectable.showOnScreen(
          rect: Rect.fromLTRB(
            caret.left - padding.left,
            caret.top - padding.top,
            caret.right + padding.right,
            caret.bottom + padding.bottom,
          ),
          duration: const Duration(milliseconds: 100),
          curve: Curves.fastOutSlowIn,
        );
        return;
      }
      final ScrollPosition? position =
          _scrollPosition ?? _host.primaryVerticalScrollPosition;
      if (position == null ||
          !position.hasContentDimensions ||
          projection.fullPlainText.isEmpty ||
          attempt >= 3) {
        return;
      }
      final double fraction = displayOffset / projection.fullPlainText.length;
      final double target = position.minScrollExtent +
          (position.maxScrollExtent - position.minScrollExtent) * fraction;
      if ((target - position.pixels).abs() < 0.5) {
        return;
      }
      unawaited(
        position
            .animateTo(
          target.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 100),
          curve: Curves.fastOutSlowIn,
        )
            .then((_) {
          if (mounted) {
            _scheduleRevealSelectionEndpoint(
              sourceOffset,
              attempt: attempt + 1,
            );
          }
        }),
      );
    });
  }

  void _handleInlineSelectionChanged() {
    if (!mounted) {
      return;
    }
    if (_selectionPointerActive && _hasPointerHitTestDragUpdate) {
      return;
    }
    if (!_selectionPointerActive && !_frameworkSelectionChanging) {
      return;
    }
    final _MarkdownInlineSelectionAggregate? selection =
        _inlineSelectionRegistry.selection;
    if (selection == null) {
      return;
    }
    if (_selectionRangeLocked && _deferViewportFreezeUntilPointerUp) {
      return;
    }
    if (_selectionRangeLocked && !_selectionPointerActive) {
      return;
    }
    _selectionCreatedByPointer =
        _selectionCreatedByPointer || _selectionPointerActive;
    _syncSelectionFromInlineRegistry(selection);
  }

  void _syncSelectionFromFramework(String plainText) {
    final _MarkdownInlineSelectionAggregate? inlineSelection =
        _inlineSelectionRegistry.selection;
    if (inlineSelection != null) {
      _syncSelectionFromInlineRegistry(inlineSelection);
      return;
    }
    _syncSelectionFromPlainText(plainText);
  }

  void _syncSelectionFromInlineRegistry(
    _MarkdownInlineSelectionAggregate selection, {
    TextSelection? directionalCompactSelection,
  }) {
    final _MarkdownSelectionProjection? projection = _projection;
    if (projection == null) {
      return;
    }
    final _MarkdownInlineSelectionAggregate resolvedSelection =
        _stabilizedSelectionForActiveDrag(selection);
    final _MarkdownSourceSelectionRange? sourceRange =
        projection.sourceRangeForPlainRange(
      resolvedSelection.compactRange,
      plainSeparator: '',
    );
    if (sourceRange == null) {
      _syncSelectionFromPlainText(_selectedContent?.plainText ?? '');
      return;
    }
    final String plainText =
        projection.plainTextForRange(resolvedSelection.displayRange);
    final TextSelection? sourceSelection = directionalCompactSelection == null
        ? null
        : projection.sourceSelectionForPlainSelection(
            directionalCompactSelection,
            plainSeparator: '',
          );
    _applySelectionSnapshot(
      plainRange: resolvedSelection.displayRange,
      compactRange: resolvedSelection.compactRange,
      sourceRange: sourceRange,
      sourceSelection: sourceSelection,
      plainText: plainText,
    );
  }

  _MarkdownInlineSelectionAggregate _stabilizedSelectionForActiveDrag(
    _MarkdownInlineSelectionAggregate selection,
  ) {
    return selection;
  }

  _MarkdownSelectionRange _orderedSelectionRange(
    int anchor,
    int extent, {
    required int max,
  }) {
    final int resolvedAnchor = anchor.clamp(0, max);
    final int resolvedExtent = extent.clamp(0, max);
    if (resolvedAnchor <= resolvedExtent) {
      return _MarkdownSelectionRange(
        start: resolvedAnchor,
        end: resolvedExtent,
      );
    }
    return _MarkdownSelectionRange(
      start: resolvedExtent,
      end: resolvedAnchor,
    );
  }

  void _syncSelectionFromPlainText(String plainText) {
    final _MarkdownSelectionProjection? projection = _projection;
    if (projection == null) {
      return;
    }
    final String selectedPlainText = plainText.replaceAll('\r', '');
    final _MarkdownSelectionRange? plainRange =
        projection.findRangeForSelectedPlainText(
      selectedPlainText,
      preferredStart: _selectionRange?.start,
    );
    final _MarkdownSourceSelectionRange? sourceRange =
        projection.sourceRangeForSelectedPlainText(
      selectedPlainText,
      preferredPlainStart: plainRange?.start ?? _selectionRange?.start,
    );
    _applySelectionSnapshot(
      plainRange: plainRange,
      compactRange: plainRange,
      sourceRange: sourceRange,
      plainText: plainRange == null
          ? selectedPlainText
          : projection.plainTextForRange(plainRange),
    );
  }

  void _applySelectionSnapshot({
    required _MarkdownSelectionRange? plainRange,
    required _MarkdownSelectionRange? compactRange,
    required _MarkdownSourceSelectionRange? sourceRange,
    TextSelection? sourceSelection,
    required String plainText,
  }) {
    final TextSelection? resolvedSourceSelection = sourceRange == null
        ? null
        : sourceSelection ??
            TextSelection(
              baseOffset: sourceRange.start,
              extentOffset: sourceRange.end,
              isDirectional: true,
            );
    final bool visualActive = _useSourceSelectionVisual &&
        plainRange != null &&
        sourceRange != null &&
        (!_selectionInteractionActive || _selectionRangeLocked);
    if (_selectionRange == plainRange &&
        _selectionCompactRange == compactRange &&
        _sourceSelectionRange == sourceRange &&
        _lastSelectedPlainText == plainText &&
        _sourceSelectionVisualActive == visualActive &&
        (resolvedSourceSelection == null ||
            _host.controller.selection == resolvedSourceSelection)) {
      return;
    }

    final bool selectionVisualChanged =
        _sourceSelectionVisualActive != visualActive ||
            (visualActive &&
                (_selectionRange != plainRange ||
                    _sourceSelectionRange != sourceRange));

    void apply() {
      _selectionRange = plainRange;
      _selectionCompactRange = compactRange;
      _sourceSelectionRange = sourceRange;
      _lastSelectedPlainText = plainText;
      _sourceSelectionVisualActive = visualActive;
      _selectionEpoch += 1;
    }

    if (resolvedSourceSelection != null) {
      final TextSelection resolvedSelection = resolvedSourceSelection;
      final TextSelection? resolvedDisplaySelection = plainRange == null
          ? null
          : TextSelection(
              baseOffset:
                  resolvedSelection.baseOffset <= resolvedSelection.extentOffset
                      ? plainRange.start
                      : plainRange.end,
              extentOffset:
                  resolvedSelection.baseOffset <= resolvedSelection.extentOffset
                      ? plainRange.end
                      : plainRange.start,
              isDirectional: true,
            );
      _updateControllerSelection(
        resolvedSelection,
        displaySelection: resolvedDisplaySelection,
      );
      if (plainRange != null) {
        final bool forward =
            resolvedSelection.baseOffset <= resolvedSelection.extentOffset;
        _inlineSelectionRegistry.applyDisplaySelection(
          TextSelection(
            baseOffset: forward ? plainRange.start : plainRange.end,
            extentOffset: forward ? plainRange.end : plainRange.start,
            isDirectional: true,
          ),
        );
      }
      if (!_selectionPointerActive && _frameworkSelectionChanging) {
        _scheduleRevealSelectionEndpoint(resolvedSelection.extentOffset);
      }
    }

    // During a native drag these ranges are bookkeeping for stable copy only.
    // Rebuilding token widgets on every pointer move makes selection feel
    // sticky, especially on web. Repaint the source-backed visual once the
    // drag has finalized or when it must be frozen for a viewport mutation.
    if (mounted && selectionVisualChanged) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _copyMarkdownSelection() {
    final _MarkdownClipboardPayloadData? data = _buildClipboardPayload();
    if (data == null) {
      return;
    }
    final String? htmlText = _selectionStrategy == SelectionStrategy.rich
        ? _selectedMarkdownToHtml(
            data.markdownText,
            allowUnclosedInlineDelimiters: _allowUnclosedInlineDelimiters,
          )
        : null;
    final MarkdownClipboardPayload payload = MarkdownClipboardPayload(
      plainText: data.plainText,
      rawMarkdown: data.markdownText,
      htmlText: htmlText,
    );
    unawaited(
      MarkdownClipboardHandler().copySelection(
        strategy: _selectionStrategy,
        payload: payload,
      ),
    );
  }

  web_copy.BrowserCopyData? _handleBrowserCopy() {
    final _MarkdownClipboardPayloadData? payload = _buildClipboardPayload();
    if (payload == null) {
      return null;
    }
    final String? htmlText = _selectionStrategy == SelectionStrategy.rich
        ? _selectedMarkdownToHtml(
            payload.markdownText,
            allowUnclosedInlineDelimiters: _allowUnclosedInlineDelimiters,
          )
        : null;
    final String plainText = switch (_selectionStrategy) {
      SelectionStrategy.plain => payload.plainText,
      SelectionStrategy.raw =>
        payload.markdownText.isEmpty ? payload.plainText : payload.markdownText,
      SelectionStrategy.rich => payload.plainText,
    };
    return web_copy.BrowserCopyData(
      plainText: plainText,
      htmlText: _selectionStrategy == SelectionStrategy.rich ? htmlText : null,
    );
  }

  _MarkdownClipboardPayloadData? _buildClipboardPayload() {
    final _MarkdownSelectionProjection? projection = _projection;
    if (projection == null) {
      return null;
    }
    final AnimatedMarkdownSelectionValue controllerValue =
        _host.controller.value;
    if (controllerValue.hasSelection) {
      final TextSelection displaySelection =
          projection.plainSelectionForSourceSelection(
        controllerValue.selection,
      );
      final _MarkdownSelectionRange displayRange = _selectionRange ??
          _MarkdownSelectionRange(
            start: displaySelection.start,
            end: displaySelection.end,
          );
      final String plainText = projection.plainTextForRange(displayRange);
      final String projectedMarkdown =
          projection.markdownForRange(displayRange);
      return _MarkdownClipboardPayloadData(
        plainText: plainText.isEmpty ? _lastSelectedPlainText : plainText,
        markdownText: projectedMarkdown.isEmpty
            ? controllerValue.selectedMarkdown
            : projectedMarkdown,
      );
    }
    final _MarkdownClipboardPayloadData? rangePayload =
        _buildRangeClipboardPayload();
    final _MarkdownSourceSelectionRange? sourceRange = _sourceSelectionRange;

    if (_selectionRangeLocked &&
        sourceRange != null &&
        (rangePayload == null ||
            _lastSelectedPlainText.length > rangePayload.plainText.length)) {
      final String markdownText =
          projection.markdownForSourceRange(sourceRange);
      if (markdownText.isNotEmpty || _lastSelectedPlainText.isNotEmpty) {
        return _MarkdownClipboardPayloadData(
          plainText: _lastSelectedPlainText,
          markdownText: markdownText,
        );
      }
    }

    if (rangePayload != null) {
      return rangePayload;
    }

    if (sourceRange != null) {
      final String markdownText =
          projection.markdownForSourceRange(sourceRange);
      if (markdownText.isNotEmpty || _lastSelectedPlainText.isNotEmpty) {
        return _MarkdownClipboardPayloadData(
          plainText: _lastSelectedPlainText,
          markdownText: markdownText,
        );
      }
    }

    final String plainText = _extractSelectedPlainText(
      projection: projection,
      selectedContent: _selectedContent,
    );
    final String markdownText = _extractSelectedRawMarkdown(
      projection: projection,
      selectedPlainText: plainText,
    );
    if (plainText.isEmpty && markdownText.isEmpty) {
      return null;
    }
    return _MarkdownClipboardPayloadData(
      plainText: plainText,
      markdownText: markdownText,
    );
  }

  _MarkdownClipboardPayloadData? _buildRangeClipboardPayload() {
    final _MarkdownSelectionProjection? projection = _projection;
    final _MarkdownSelectionRange? range = _selectionRange;
    if (range != null && projection != null) {
      final String plainText = projection.plainTextForRange(range);
      final String markdownText = projection.markdownForRange(range);
      if (plainText.isNotEmpty || markdownText.isNotEmpty) {
        return _MarkdownClipboardPayloadData(
          plainText: plainText,
          markdownText: markdownText,
        );
      }
    }
    return null;
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      if (_host.controller.value.hasSelection) {
        _ignoreFrameworkDragUpdatesUntilFinalized = false;
        _applyControllerSelection(reveal: false);
        _activateCurrentSourceSelectionVisual();
      }
      return;
    }
    if (_inAppPrimaryPointers.isNotEmpty && _focusMovedWithinApplication) {
      _clearSelectionCache();
      return;
    }
    if (_host.controller.value.hasSelection) {
      _preserveSelectionAfterExternalFocusLoss();
      return;
    }
    _clearSelectionCache();
  }

  bool get _focusMovedWithinApplication {
    final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
    // Browser/window blur falls back to an enclosing focus scope, whereas a
    // pointer transfer to another Flutter control lands on a concrete node.
    return primaryFocus != null &&
        primaryFocus is! FocusScopeNode &&
        !identical(primaryFocus, _focusNode) &&
        primaryFocus.context != null;
  }

  void _preserveSelectionAfterExternalFocusLoss() {
    if (!_host.controller.value.hasSelection) {
      return;
    }
    _frameworkSelectionChanging = false;
    _selectionPointerActive = false;
    _activeSelectionPointer = null;
    _ignoreFrameworkDragUpdatesUntilFinalized = true;
    _plainClickDismissalPending = false;
    _host.finalize();
    _stopSelectionAutoScroll(clearDragPosition: true);
    _applyControllerSelection(reveal: false);
    _activateCurrentSourceSelectionVisual();
  }

  void _handleScrollActivity() {
    if (_host.isAutoScrolling) {
      return;
    }
    if (_selectionPointerActive &&
        _sourceSelectionRange != null &&
        _scrollPosition?.isScrollingNotifier.value == true) {
      _freezeSelectionForViewportMutation();
      return;
    }
    _lastScrollPixels = _scrollPosition?.pixels;
  }

  void _handleScrollOffsetChanged() {
    final ScrollPosition? scrollPosition = _scrollPosition;
    if (scrollPosition == null) {
      return;
    }
    final double previousPixels = _lastScrollPixels ?? scrollPosition.pixels;
    final double pixels = scrollPosition.pixels;
    _lastScrollPixels = pixels;
    if (_host.isAutoScrolling) {
      return;
    }
    if ((pixels - previousPixels).abs() < 0.001) {
      return;
    }
    if (_selectionPointerActive && _sourceSelectionRange != null) {
      _freezeSelectionForViewportMutation();
    }
  }

  void _handleSelectableRegionStatusChanged(dynamic status) {
    if (_suppressFrameworkSelectionClear) {
      return;
    }
    final String statusName = status.toString().split('.').last;
    if (statusName == 'changing') {
      _host.beginDrag();
      _frameworkSelectionChanging = true;
      if (_selectionRangeLocked && _sourceSelectionRange != null) {
        return;
      }
      _setSourceSelectionVisualActive(false);
      return;
    }
    if (statusName == 'finalized') {
      _host.finalize();
      _frameworkSelectionChanging = false;
      _ignoreFrameworkDragUpdatesUntilFinalized = false;
      _stopSelectionAutoScroll(clearDragPosition: true);
      _activateCurrentSourceSelectionVisual();
      _scheduleFinalizedGeometrySync();
    }
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _trackInAppPointerDown(event);
      if (_activeSelectionPointer == event.pointer ||
          !_isPrimarySelectionPointer(event)) {
        return;
      }
      final _MarkdownInlineSelectionDragUpdate? update =
          _inlineSelectionRegistry.dragUpdateForGlobalPosition(event.position);
      if (update == null) {
        return;
      }
      final _MarkdownSelectionRange? displayRange = _selectionRange;
      final _MarkdownSelectionRange? compactRange = _selectionCompactRange;
      final bool touchesStart =
          displayRange != null && update.displayOffset == displayRange.start;
      final bool touchesEnd =
          displayRange != null && update.displayOffset == displayRange.end;
      if ((touchesStart || touchesEnd) && compactRange != null) {
        _cancelSelectionReleaseGuard();
        _selectionPointerActive = true;
        _activeSelectionPointer = event.pointer;
        _selectionCreatedByPointer = true;
        _ignoreFrameworkDragUpdatesUntilFinalized = false;
        _hasPointerHitTestDragUpdate = false;
        _beginPointerInteraction();
        _host.beginDrag();
        _setSourceSelectionVisualActive(false);
        _selectionDragAnchor = _MarkdownSelectionDragAnchor(
          displayOffset: touchesStart ? displayRange.end : displayRange.start,
          compactOffset: touchesStart ? compactRange.end : compactRange.start,
        );
        _selectionDragOriginGlobalPosition = event.position;
        _lastSelectionDragGlobalPosition = event.position;
        return;
      }
      _handlePointerDown(event);
      return;
    }
    if (event is PointerMoveEvent) {
      if (_activeSelectionPointer != event.pointer) {
        return;
      }
      _handleSelectionDragPositionChanged(event.position);
      final _MarkdownInlineSelectionDragUpdate? update =
          _inlineSelectionRegistry.dragUpdateForGlobalPosition(event.position);
      if (update != null) {
        _handleInlineSelectionDragUpdate(
          update,
          fromPointerHitTest: true,
        );
      }
      return;
    }
    if (event is! PointerUpEvent && event is! PointerCancelEvent) {
      return;
    }
    _trackInAppPointerFinished(event.pointer);
    if (_activeSelectionPointer != event.pointer &&
        !_frameworkSelectionChanging &&
        !_host.isAutoScrolling) {
      return;
    }
    _frameworkSelectionChanging = false;
    _selectionPointerActive = false;
    _activeSelectionPointer = null;
    final bool dismissedPlainClick = _schedulePlainClickDismissal();
    _armSelectionReleaseGuard();
    _host.finalize();
    _stopSelectionAutoScroll(clearDragPosition: true);
    if (!dismissedPlainClick) {
      _activateCurrentSourceSelectionVisual();
      _scheduleFinalizedGeometrySync();
    }
  }

  void _clearSelectionCache({bool notify = false}) {
    _inlineSelectionRegistry.applyDisplaySelection(null);
    void clear() {
      _selectedContent = null;
      _selectionRange = null;
      _selectionCompactRange = null;
      _sourceSelectionRange = null;
      _selectionDragAnchor = null;
      _lastSelectedPlainText = '';
      _selectionRangeLocked = false;
      _suppressFrameworkSelectionClear = false;
      _sourceSelectionVisualActive = false;
      _frameworkSelectionClearScheduled = false;
      _selectionCreatedByPointer = false;
      _deferViewportFreezeUntilPointerUp = false;
      _frameworkSelectionChanging = false;
      _ignoreFrameworkDragUpdatesUntilFinalized = false;
      _hasPointerHitTestDragUpdate = false;
      _plainClickDismissalPending = false;
      _cancelSelectionReleaseGuard();
      _selectionEpoch += 1;
      _lastScrollPixels = _scrollPosition?.pixels;
      _stopSelectionAutoScroll(clearDragPosition: true);
    }

    _updateControllerSelection(
      const TextSelection.collapsed(offset: -1),
    );
    _host.clearPhase();

    if (notify && mounted) {
      setState(clear);
    } else {
      clear();
    }
  }

  void _clearFrameworkSelectionVisual() {
    final State<StatefulWidget>? state = _selectionAreaKey.currentState;
    if (state == null) {
      return;
    }
    _suppressFrameworkSelectionClear = true;
    try {
      // SelectionAreaState became public after Flutter 3.10. Keep the newer
      // path dynamic so the package still compiles against the minimum SDK.
      final dynamic selectableRegion = (state as dynamic).selectableRegion;
      selectableRegion.clearSelection();
    } on NoSuchMethodError {
      // Flutter 3.10 keeps SelectionArea's state private. Clearing each
      // registered selectable still publishes SelectionGeometry.none to the
      // enclosing SelectableRegion and removes its native highlight.
      _inlineSelectionRegistry.clearFrameworkSelectionGeometry();
    }
    _selectedContent = null;
    _setSourceSelectionVisualActive(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _suppressFrameworkSelectionClear = false;
      }
    });
  }

  void _freezeSelectionForViewportMutation({bool deferClear = false}) {
    _resolvePendingSelectionSnapshot();
    if (_sourceSelectionRange == null) {
      return;
    }
    if (_selectionPointerActive) {
      _selectionRangeLocked = true;
      _deferViewportFreezeUntilPointerUp = true;
      _setSourceSelectionVisualActive(true);
      return;
    }
    _selectionRangeLocked = true;
    if (deferClear) {
      _setSourceSelectionVisualActive(true);
      _scheduleFrameworkSelectionClear();
      return;
    }
    _clearFrameworkSelectionVisual();
  }

  void _scheduleFrameworkSelectionClear() {
    if (_frameworkSelectionClearScheduled) {
      return;
    }
    final int epoch = _selectionEpoch;
    _frameworkSelectionClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted) {
          return;
        }
        _frameworkSelectionClearScheduled = false;
        if (epoch != _selectionEpoch) {
          return;
        }
        _clearFrameworkSelectionVisual();
      });
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isPrimarySelectionPointer(event)) {
      return;
    }
    if (_activeSelectionPointer == event.pointer) {
      return;
    }
    _cancelSelectionReleaseGuard();
    if (_sourceSelectionRange != null || _host.controller.value.hasSelection) {
      _clearFrameworkSelectionVisual();
      _clearSelectionCache(notify: _sourceSelectionVisualActive);
    } else {
      _setSourceSelectionVisualActive(false);
    }
    _selectionPointerActive = true;
    _beginPointerInteraction();
    _host.beginDrag();
    _activeSelectionPointer = event.pointer;
    _selectionCreatedByPointer = true;
    _ignoreFrameworkDragUpdatesUntilFinalized = false;
    _hasPointerHitTestDragUpdate = false;
    _selectionDragAnchor = null;
    _selectionDragOriginGlobalPosition = event.position;
    final _MarkdownInlineSelectionDragUpdate? pointerAnchor =
        _inlineSelectionRegistry.dragUpdateForGlobalPosition(event.position);
    if (pointerAnchor != null) {
      _selectionDragAnchor = _MarkdownSelectionDragAnchor(
        displayOffset: pointerAnchor.displayOffset,
        compactOffset: pointerAnchor.compactOffset,
      );
    }
    _lastSelectionDragGlobalPosition = event.position;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activeSelectionPointer != event.pointer) {
      return;
    }
    _handleSelectionDragPositionChanged(event.position);
  }

  void _handlePointerFinished(PointerEvent event) {
    if (_activeSelectionPointer != event.pointer) {
      return;
    }
    _activeSelectionPointer = null;
    _selectionPointerActive = false;
    final bool dismissedPlainClick = _schedulePlainClickDismissal();
    _armSelectionReleaseGuard();
    _host.finalize();
    _ignoreFrameworkDragUpdatesUntilFinalized = true;
    _stopSelectionAutoScroll(clearDragPosition: true);
    if (_deferViewportFreezeUntilPointerUp) {
      _deferViewportFreezeUntilPointerUp = false;
      _freezeSelectionForViewportMutation(deferClear: true);
      return;
    }
    if (!dismissedPlainClick) {
      _activateCurrentSourceSelectionVisual();
      _scheduleFinalizedGeometrySync();
    }
  }

  void _armSelectionReleaseGuard() {
    _selectionReleasePendingFinalize = true;
    final int epoch = ++_selectionReleaseGuardEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _selectionReleaseGuardEpoch) {
        return;
      }
      _selectionReleasePendingFinalize = false;
      // The framework's scrollable selection delegate is private. Keeping the
      // proxy pending through pointer finalization stops that delegate; this
      // second cancellation also covers SDKs whose final activity starts late.
      _host.stopAutoScroll();
    });
  }

  void _cancelSelectionReleaseGuard() {
    _selectionReleaseGuardEpoch += 1;
    _selectionReleasePendingFinalize = false;
  }

  void _scheduleFinalizedGeometrySync() {
    if (_finalizedGeometrySyncScheduled) {
      return;
    }
    _finalizedGeometrySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finalizedGeometrySyncScheduled = false;
      if (!mounted || _selectionPointerActive) {
        return;
      }
      _applyControllerSelection(reveal: false);
    });
  }

  void _resolvePendingSelectionSnapshot() {
    if (_sourceSelectionRange != null) {
      return;
    }
    final String selectedPlainText =
        (_selectedContent?.plainText ?? '').replaceAll('\r', '');
    if (selectedPlainText.isEmpty) {
      return;
    }
    _syncSelectionFromPlainText(selectedPlainText);
  }

  void _handleInlineSelectionDragUpdate(
    _MarkdownInlineSelectionDragUpdate update, {
    bool fromPointerHitTest = false,
  }) {
    if (_selectionRangeLocked) {
      return;
    }
    if (!_selectionPointerActive && !_frameworkSelectionChanging) {
      return;
    }
    if (!fromPointerHitTest &&
        _selectionPointerActive &&
        _hasPointerHitTestDragUpdate) {
      return;
    }
    if (_ignoreFrameworkDragUpdatesUntilFinalized && !_selectionPointerActive) {
      return;
    }
    _hasPointerHitTestDragUpdate =
        _hasPointerHitTestDragUpdate || fromPointerHitTest;
    _host.leaseGeometryAtDisplayOffset(update.displayOffset);
    _handleSelectionDragPositionChanged(update.globalPosition);
    _syncSelectionFromActiveDragUpdate(update);
  }

  void _syncSelectionFromActiveDragUpdate(
    _MarkdownInlineSelectionDragUpdate update,
  ) {
    if (_selectionRangeLocked) {
      return;
    }
    if (!_selectionPointerActive && !_frameworkSelectionChanging) {
      return;
    }
    final _MarkdownInlineSelectionAggregate? selection =
        (_selectionDragAnchor != null
                ? _selectionAggregateFromDragAnchor(update)
                : null) ??
            _inlineSelectionRegistry.selection ??
            _selectionAggregateFromDragAnchor(update);
    if (selection == null) {
      return;
    }
    _selectionCreatedByPointer =
        _selectionCreatedByPointer || _selectionPointerActive;
    final _MarkdownSelectionDragAnchor? anchor = _selectionDragAnchor;
    final TextSelection? directionalCompactSelection = anchor == null
        ? null
        : TextSelection(
            baseOffset:
                update.isEnd ? anchor.compactOffset : update.compactOffset,
            extentOffset:
                update.isEnd ? update.compactOffset : anchor.compactOffset,
            isDirectional: true,
          );
    _syncSelectionFromInlineRegistry(
      selection,
      directionalCompactSelection: directionalCompactSelection,
    );
  }

  _MarkdownInlineSelectionAggregate? _selectionAggregateFromDragAnchor(
    _MarkdownInlineSelectionDragUpdate update,
  ) {
    final _MarkdownSelectionDragAnchor? anchor = _selectionDragAnchor;
    final _MarkdownSelectionProjection? projection = _projection;
    if (anchor == null || projection == null) {
      return null;
    }
    final _MarkdownSelectionRange displayRange = _orderedSelectionRange(
      anchor.displayOffset,
      update.displayOffset,
      max: projection.fullPlainText.length,
    );
    final _MarkdownSelectionRange compactRange = _orderedSelectionRange(
      anchor.compactOffset,
      update.compactOffset,
      max: projection.compactPlainText.length,
    );
    if (displayRange.start >= displayRange.end ||
        compactRange.start >= compactRange.end) {
      return null;
    }
    return _MarkdownInlineSelectionAggregate(
      displayRange: displayRange,
      compactRange: compactRange,
    );
  }

  void _detachScrollPosition() {
    _stopSelectionAutoScroll(clearDragPosition: false);
    _scrollPosition?.isScrollingNotifier.removeListener(_handleScrollActivity);
    _scrollPosition?.removeListener(_handleScrollOffsetChanged);
    _host.unregisterScrollable(_scrollOwner);
    _scrollableState = null;
    _scrollPosition = null;
    _lastScrollPixels = null;
  }

  bool _isPrimarySelectionPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return (event.buttons & kPrimaryButton) != 0;
    }
    if (event.kind == PointerDeviceKind.trackpad) {
      return (event.buttons & kPrimaryButton) != 0 || event.buttons == 0;
    }
    if (event.kind == PointerDeviceKind.stylus) {
      return (event.buttons & kPrimaryStylusButton) != 0 ||
          (event.buttons & kPrimaryButton) != 0;
    }
    return false;
  }

  void _trackInAppPointerDown(PointerDownEvent event) {
    final bool primary = (event.buttons & kPrimaryButton) != 0 ||
        (event.kind == PointerDeviceKind.trackpad && event.buttons == 0);
    if (primary) {
      _inAppPrimaryPointers.add(event.pointer);
    }
  }

  void _trackInAppPointerFinished(int pointer) {
    if (!_inAppPrimaryPointers.contains(pointer)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inAppPrimaryPointers.remove(pointer);
    });
  }

  void _handleSelectionDragPositionChanged(Offset globalPosition) {
    if (!mounted) {
      return;
    }
    final Offset origin = _selectionDragOriginGlobalPosition ?? globalPosition;
    _selectionDragOriginGlobalPosition ??= globalPosition;
    _lastSelectionDragGlobalPosition = globalPosition;
    final Offset delta = globalPosition - origin;
    if (delta.distanceSquared > 1) {
      _selectionPointerMoved = true;
    }
    _selectionDragAxisIntent = <Axis>{
      if (delta.dx.abs() > 1) Axis.horizontal,
      if (delta.dy.abs() > 1) Axis.vertical,
    };
    _host.startAutoScroll(globalPosition, _selectionDragAxisIntent);
  }

  void _beginPointerInteraction() {
    _pointerInteractionEpoch += 1;
    _selectionPointerMoved = false;
    _discretePointerSelection = false;
    _plainClickDismissalPending = false;
  }

  void _handleDiscretePointerSelection() {
    _discretePointerSelection = true;
    _plainClickDismissalPending = false;
  }

  bool _schedulePlainClickDismissal() {
    if (_selectionPointerMoved || _discretePointerSelection) {
      return false;
    }
    final int epoch = _pointerInteractionEpoch;
    // Clear both selection sources before the next paint. Waiting until a
    // post-frame callback lets SelectableRegion expose its temporary
    // line-start-to-caret range for one frame on web and desktop.
    _ignoreFrameworkDragUpdatesUntilFinalized = true;
    _clearFrameworkSelectionVisual();
    _clearSelectionCache(notify: true);
    _plainClickDismissalPending = true;
    _ignoreFrameworkDragUpdatesUntilFinalized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted ||
            epoch != _pointerInteractionEpoch ||
            _selectionPointerActive ||
            _selectionPointerMoved ||
            _discretePointerSelection) {
          return;
        }
        _clearFrameworkSelectionVisual();
        _clearSelectionCache(notify: true);
      });
    });
    return true;
  }

  void _handleSelectionAutoScrollFrame() {
    final Offset? globalPosition = _lastSelectionDragGlobalPosition;
    if (!mounted || globalPosition == null) {
      return;
    }
    _host.startAutoScroll(globalPosition, _selectionDragAxisIntent);
    _lastScrollPixels = _scrollPosition?.pixels;
    final _MarkdownInlineSelectionDragUpdate? update =
        _inlineSelectionRegistry.dragUpdateForGlobalPosition(globalPosition);
    if (update != null) {
      _syncSelectionFromActiveDragUpdate(update);
    }
  }

  void _stopSelectionAutoScroll({
    required bool clearDragPosition,
    bool cancelScrollActivity = true,
  }) {
    _host.stopAutoScroll(cancelScrollActivity: cancelScrollActivity);
    _lastScrollPixels = _scrollPosition?.pixels;
    if (clearDragPosition) {
      _lastSelectionDragGlobalPosition = null;
      _selectionDragOriginGlobalPosition = null;
      _selectionDragAxisIntent = const <Axis>{};
    }
  }

  void _setSourceSelectionVisualActive(bool active) {
    if (_sourceSelectionVisualActive == active) {
      return;
    }
    if (!mounted) {
      _sourceSelectionVisualActive = active;
      return;
    }
    setState(() {
      _sourceSelectionVisualActive = active;
    });
  }

  void _activateCurrentSourceSelectionVisual() {
    if (!_useSourceSelectionVisual ||
        (_selectionInteractionActive && !_selectionRangeLocked) ||
        _selectionRange == null ||
        _sourceSelectionRange == null) {
      return;
    }
    _setSourceSelectionVisualActive(true);
  }
}

class _MarkdownSourceSelectionVisualScope extends InheritedWidget {
  const _MarkdownSourceSelectionVisualScope({
    required this.sourceRange,
    required this.plainRange,
    required this.selectionColor,
    required super.child,
  });

  final _MarkdownSourceSelectionRange? sourceRange;
  final _MarkdownSelectionRange? plainRange;
  final Color selectionColor;

  @override
  bool updateShouldNotify(
    covariant _MarkdownSourceSelectionVisualScope oldWidget,
  ) {
    return sourceRange != oldWidget.sourceRange ||
        plainRange != oldWidget.plainRange ||
        selectionColor != oldWidget.selectionColor;
  }
}

class _MarkdownSelectionAutoScrollRegionHost extends StatefulWidget {
  const _MarkdownSelectionAutoScrollRegionHost({
    required this.axis,
    required this.builder,
  });

  final Axis axis;
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  State<_MarkdownSelectionAutoScrollRegionHost> createState() =>
      _MarkdownSelectionAutoScrollRegionHostState();
}

class _MarkdownSelectionAutoScrollRegionHostState
    extends State<_MarkdownSelectionAutoScrollRegionHost> {
  late final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }
}

class _MarkdownInlineSelectionRegistryScope extends InheritedWidget {
  const _MarkdownInlineSelectionRegistryScope({
    required this.registry,
    required super.child,
  });

  final _MarkdownInlineSelectionRegistry registry;

  static _MarkdownInlineSelectionRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<
            _MarkdownInlineSelectionRegistryScope>()
        ?.registry;
  }

  @override
  bool updateShouldNotify(
    covariant _MarkdownInlineSelectionRegistryScope oldWidget,
  ) {
    return registry != oldWidget.registry;
  }
}

class _MarkdownInlineSelectionRegistry extends ChangeNotifier {
  final Map<Selectable, _MarkdownInlineSelectionSnapshot> _selections =
      <Selectable, _MarkdownInlineSelectionSnapshot>{};
  final Set<_RenderSelectableInlineTextProxy> _selectables =
      <_RenderSelectableInlineTextProxy>{};
  final List<ValueChanged<_MarkdownInlineSelectionDragUpdate>>
      _dragUpdateListeners =
      <ValueChanged<_MarkdownInlineSelectionDragUpdate>>[];
  TextSelection? _displaySelection;
  bool _applyingDisplaySelection = false;
  bool Function()? shouldReturnPending;
  bool Function()? shouldIgnoreFrameworkEdgeUpdate;
  VoidCallback? onDiscreteSelection;

  SelectionResult resolveSelectionResult(SelectionResult fallback) {
    return shouldReturnPending?.call() ?? false
        ? SelectionResult.pending
        : fallback;
  }

  _MarkdownInlineSelectionAggregate? get selection {
    if (_selections.isEmpty) {
      return null;
    }
    int? displayStart;
    int? displayEnd;
    int? compactStart;
    int? compactEnd;
    for (final _MarkdownInlineSelectionSnapshot snapshot
        in _selections.values) {
      displayStart = displayStart == null
          ? snapshot.displayRange.start
          : (displayStart < snapshot.displayRange.start
              ? displayStart
              : snapshot.displayRange.start);
      displayEnd = displayEnd == null
          ? snapshot.displayRange.end
          : (displayEnd > snapshot.displayRange.end
              ? displayEnd
              : snapshot.displayRange.end);
      compactStart = compactStart == null
          ? snapshot.compactRange.start
          : (compactStart < snapshot.compactRange.start
              ? compactStart
              : snapshot.compactRange.start);
      compactEnd = compactEnd == null
          ? snapshot.compactRange.end
          : (compactEnd > snapshot.compactRange.end
              ? compactEnd
              : snapshot.compactRange.end);
    }
    if (displayStart == null ||
        displayEnd == null ||
        compactStart == null ||
        compactEnd == null ||
        displayStart >= displayEnd ||
        compactStart >= compactEnd) {
      return null;
    }
    return _MarkdownInlineSelectionAggregate(
      displayRange: _MarkdownSelectionRange(
        start: displayStart,
        end: displayEnd,
      ),
      compactRange: _MarkdownSelectionRange(
        start: compactStart,
        end: compactEnd,
      ),
    );
  }

  void update(
    Selectable selectable, {
    required _MarkdownSelectionRange displayRange,
    required _MarkdownSelectionRange compactRange,
  }) {
    final _MarkdownInlineSelectionSnapshot next =
        _MarkdownInlineSelectionSnapshot(
      displayRange: displayRange,
      compactRange: compactRange,
    );
    if (_selections[selectable] == next) {
      return;
    }
    _selections[selectable] = next;
    if (!_applyingDisplaySelection) {
      notifyListeners();
    }
  }

  void clear(Selectable selectable, {bool notify = true}) {
    if (_selections.remove(selectable) == null) {
      return;
    }
    if (notify && !_applyingDisplaySelection) {
      notifyListeners();
    }
  }

  void registerSelectable(_RenderSelectableInlineTextProxy selectable) {
    _selectables.add(selectable);
    final bool wasApplying = _applyingDisplaySelection;
    _applyingDisplaySelection = true;
    try {
      selectable.applyDisplaySelection(_displaySelection);
    } finally {
      _applyingDisplaySelection = wasApplying;
    }
  }

  void unregisterSelectable(_RenderSelectableInlineTextProxy selectable) {
    _selectables.remove(selectable);
  }

  void applyDisplaySelection(TextSelection? selection) {
    _displaySelection = selection;
    final bool wasApplying = _applyingDisplaySelection;
    _applyingDisplaySelection = true;
    try {
      for (final _RenderSelectableInlineTextProxy selectable
          in _selectables.toList(growable: false)) {
        if (selectable.attached) {
          selectable.applyDisplaySelection(selection);
        }
      }
    } finally {
      _applyingDisplaySelection = wasApplying;
    }
  }

  void clearFrameworkSelectionGeometry() {
    final bool wasApplying = _applyingDisplaySelection;
    _applyingDisplaySelection = true;
    try {
      for (final _RenderSelectableInlineTextProxy selectable
          in _selectables.toList(growable: false)) {
        if (selectable.attached) {
          selectable.clearFrameworkSelectionGeometry();
        }
      }
    } finally {
      _applyingDisplaySelection = wasApplying;
    }
  }

  _RenderSelectableInlineTextProxy? selectableForDisplayOffset(
    int offset, {
    bool allowClosest = true,
  }) {
    _RenderSelectableInlineTextProxy? closest;
    int closestDistance = 1 << 30;
    for (final _RenderSelectableInlineTextProxy selectable in _selectables) {
      if (!selectable.attached || !selectable.hasSize) {
        continue;
      }
      final int start = selectable.absolutePlainTextStart;
      final int end = start + selectable.plainText.length;
      if (offset >= start && offset <= end) {
        return selectable;
      }
      final int distance = offset < start ? start - offset : offset - end;
      if (distance < closestDistance) {
        closest = selectable;
        closestDistance = distance;
      }
    }
    return allowClosest ? closest : null;
  }

  _MarkdownInlineSelectionDragUpdate? dragUpdateForGlobalPosition(
    Offset globalPosition,
  ) {
    _RenderSelectableInlineTextProxy? best;
    double bestDistance = double.infinity;
    bool bestContains = false;
    for (final _RenderSelectableInlineTextProxy selectable
        in _selectables.toList(growable: false)) {
      if (!selectable.attached ||
          !selectable.hasSize ||
          selectable.plainText.isEmpty) {
        continue;
      }
      final Rect rect = selectable.localToGlobal(Offset.zero) & selectable.size;
      final bool contains = rect.inflate(4).contains(globalPosition);
      final double distance =
          contains ? 0 : _distanceFromPointToRect(globalPosition, rect);
      if (best == null ||
          (contains && !bestContains) ||
          (contains == bestContains && distance < bestDistance)) {
        best = selectable;
        bestContains = contains;
        bestDistance = distance;
      }
    }
    if (best == null || (!bestContains && bestDistance > 72 * 72)) {
      return null;
    }
    final Offset localPosition = best.globalToLocal(globalPosition);
    final int offset = best._positionForLocalOffset(localPosition);
    return _MarkdownInlineSelectionDragUpdate(
      globalPosition: globalPosition,
      displayOffset: best.absolutePlainTextStart + offset,
      compactOffset: best.compactPlainTextStart + offset,
      isEnd: true,
    );
  }

  double _distanceFromPointToRect(Offset point, Rect rect) {
    final double dx = point.dx < rect.left
        ? rect.left - point.dx
        : point.dx > rect.right
            ? point.dx - rect.right
            : 0;
    final double dy = point.dy < rect.top
        ? rect.top - point.dy
        : point.dy > rect.bottom
            ? point.dy - rect.bottom
            : 0;
    return dx * dx + dy * dy;
  }

  void addDragUpdateListener(
    ValueChanged<_MarkdownInlineSelectionDragUpdate> listener,
  ) {
    _dragUpdateListeners.add(listener);
  }

  void removeDragUpdateListener(
    ValueChanged<_MarkdownInlineSelectionDragUpdate> listener,
  ) {
    _dragUpdateListeners.remove(listener);
  }

  void reportDragUpdate(_MarkdownInlineSelectionDragUpdate update) {
    final List<ValueChanged<_MarkdownInlineSelectionDragUpdate>> listeners =
        List<ValueChanged<_MarkdownInlineSelectionDragUpdate>>.of(
      _dragUpdateListeners,
    );
    for (final ValueChanged<_MarkdownInlineSelectionDragUpdate> listener
        in listeners) {
      listener(update);
    }
  }

  void reportDiscreteSelection() {
    onDiscreteSelection?.call();
  }

  @override
  void dispose() {
    _displaySelection = null;
    shouldReturnPending = null;
    shouldIgnoreFrameworkEdgeUpdate = null;
    onDiscreteSelection = null;
    _selectables.clear();
    _dragUpdateListeners.clear();
    super.dispose();
  }
}

class _MarkdownSelectionDragAnchor {
  const _MarkdownSelectionDragAnchor({
    required this.displayOffset,
    required this.compactOffset,
  });

  final int displayOffset;
  final int compactOffset;
}

class _MarkdownInlineSelectionDragUpdate {
  const _MarkdownInlineSelectionDragUpdate({
    required this.globalPosition,
    required this.displayOffset,
    required this.compactOffset,
    required this.isEnd,
  });

  final Offset globalPosition;
  final int displayOffset;
  final int compactOffset;
  final bool isEnd;
}

class _MarkdownInlineSelectionSnapshot {
  const _MarkdownInlineSelectionSnapshot({
    required this.displayRange,
    required this.compactRange,
  });

  final _MarkdownSelectionRange displayRange;
  final _MarkdownSelectionRange compactRange;

  @override
  bool operator ==(Object other) {
    return other is _MarkdownInlineSelectionSnapshot &&
        other.displayRange == displayRange &&
        other.compactRange == compactRange;
  }

  @override
  int get hashCode => Object.hash(displayRange, compactRange);
}

class _MarkdownInlineSelectionAggregate {
  const _MarkdownInlineSelectionAggregate({
    required this.displayRange,
    required this.compactRange,
  });

  final _MarkdownSelectionRange displayRange;
  final _MarkdownSelectionRange compactRange;
}

class _MarkdownSelectionBlockVisualScope extends InheritedWidget {
  const _MarkdownSelectionBlockVisualScope({
    required this.blockRange,
    required super.child,
  });

  final _MarkdownSelectionBlockRange blockRange;

  static _MarkdownSelectionBlockVisualScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        _MarkdownSelectionBlockVisualScope>();
  }

  @override
  bool updateShouldNotify(
    covariant _MarkdownSelectionBlockVisualScope oldWidget,
  ) {
    return blockRange != oldWidget.blockRange;
  }
}

class _SelectableRegionStatusListener extends StatefulWidget {
  const _SelectableRegionStatusListener({
    required this.onStatusChanged,
    required this.child,
  });

  final ValueChanged<dynamic> onStatusChanged;
  final Widget child;

  @override
  State<_SelectableRegionStatusListener> createState() =>
      _SelectableRegionStatusListenerState();
}

class _SelectableRegionStatusListenerState
    extends State<_SelectableRegionStatusListener> {
  dynamic _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    dynamic nextStatus;
    context.visitAncestorElements((Element element) {
      final dynamic ancestor = element.widget;
      if (ancestor.runtimeType.toString() !=
          'SelectableRegionSelectionStatusScope') {
        return true;
      }
      try {
        nextStatus = ancestor.selectionStatusNotifier;
      } on NoSuchMethodError {
        nextStatus = null;
      }
      return false;
    });
    if (nextStatus == _status) {
      return;
    }
    _status?.removeListener(_handleStatusChanged);
    _status = nextStatus;
    _status?.addListener(_handleStatusChanged);
  }

  @override
  void dispose() {
    _status?.removeListener(_handleStatusChanged);
    super.dispose();
  }

  void _handleStatusChanged() {
    final dynamic status = _status?.value;
    if (status == null) {
      return;
    }
    widget.onStatusChanged(status);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MarkdownClipboardPayloadData {
  const _MarkdownClipboardPayloadData({
    required this.plainText,
    required this.markdownText,
  });

  final String plainText;
  final String markdownText;
}
