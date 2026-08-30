part of '../view.dart';

class _InlineSelectionRevealController extends ChangeNotifier {
  int _revealedTextLength = 0;
  bool _notificationScheduled = false;

  int get revealedTextLength => _revealedTextLength;

  void revealThrough(int textLength) {
    if (textLength <= _revealedTextLength) {
      return;
    }
    _revealedTextLength = textLength;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notificationScheduled) {
      return;
    }
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      notifyListeners();
    });
  }
}

class _ProgressiveSelectableInlineTextProxy extends StatefulWidget {
  const _ProgressiveSelectableInlineTextProxy({
    required this.revealController,
    required this.plainText,
    required this.absolutePlainTextStart,
    required this.compactPlainTextStart,
    required this.text,
    required this.textDirection,
    required this.textScale,
    required this.selectionColor,
    required this.registrar,
    required this.selectionRegistry,
    required this.child,
  });

  final _InlineSelectionRevealController revealController;
  final String plainText;
  final int absolutePlainTextStart;
  final int compactPlainTextStart;
  final TextSpan text;
  final TextDirection textDirection;
  final _MarkdownTextScale textScale;
  final Color? selectionColor;
  final SelectionRegistrar? registrar;
  final _MarkdownInlineSelectionRegistry? selectionRegistry;
  final Widget child;

  @override
  State<_ProgressiveSelectableInlineTextProxy> createState() =>
      _ProgressiveSelectableInlineTextProxyState();
}

class _ProgressiveSelectableInlineTextProxyState
    extends State<_ProgressiveSelectableInlineTextProxy> {
  int _revealedTextLength = 0;

  @override
  void initState() {
    super.initState();
    widget.revealController.addListener(_handleRevealChanged);
    _revealedTextLength = widget.revealController.revealedTextLength;
  }

  @override
  void didUpdateWidget(
      covariant _ProgressiveSelectableInlineTextProxy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealController != widget.revealController) {
      oldWidget.revealController.removeListener(_handleRevealChanged);
      if (widget.plainText.startsWith(oldWidget.plainText)) {
        widget.revealController.revealThrough(
          oldWidget.revealController.revealedTextLength,
        );
      }
      widget.revealController.addListener(_handleRevealChanged);
      oldWidget.revealController.dispose();
    }
    if (!widget.plainText.startsWith(oldWidget.plainText)) {
      _revealedTextLength = 0;
    }
    _revealedTextLength =
        _revealedTextLength.clamp(0, widget.plainText.length).toInt();
    if (widget.revealController.revealedTextLength > _revealedTextLength) {
      _revealedTextLength = widget.revealController.revealedTextLength;
    }
  }

  @override
  void dispose() {
    widget.revealController.removeListener(_handleRevealChanged);
    widget.revealController.dispose();
    super.dispose();
  }

  void _handleRevealChanged() {
    final int next = widget.revealController.revealedTextLength.clamp(
      0,
      widget.plainText.length,
    );
    if (!mounted || next <= _revealedTextLength) {
      return;
    }
    setState(() {
      _revealedTextLength = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int length = _revealedTextLength.clamp(0, widget.plainText.length);
    return _SelectableInlineTextProxy(
      plainText: widget.plainText.substring(0, length),
      absolutePlainTextStart: widget.absolutePlainTextStart,
      compactPlainTextStart: widget.compactPlainTextStart,
      text: _selectionTextSpanPrefix(widget.text, length),
      textDirection: widget.textDirection,
      textScale: widget.textScale,
      selectionColor: widget.selectionColor,
      registrar: widget.registrar,
      selectionRegistry: widget.selectionRegistry,
      child: widget.child,
    );
  }
}

TextSpan _selectionTextSpanPrefix(TextSpan span, int length) {
  if (length >= span.toPlainText().length) {
    return span;
  }
  int remaining = length;
  final List<InlineSpan> children = <InlineSpan>[];
  final String? ownText = span.text;
  String? clippedText;
  if (ownText != null && remaining > 0) {
    final int take = remaining.clamp(0, ownText.length);
    clippedText = ownText.substring(0, take);
    remaining -= take;
  }
  for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
    if (remaining <= 0) {
      break;
    }
    if (child is TextSpan) {
      final int childLength = child.toPlainText().length;
      children.add(_selectionTextSpanPrefix(child, remaining));
      remaining -= childLength.clamp(0, remaining);
    }
  }
  return TextSpan(text: clippedText, style: span.style, children: children);
}

class _SelectableInlineTextProxy extends SingleChildRenderObjectWidget {
  const _SelectableInlineTextProxy({
    required this.plainText,
    required this.absolutePlainTextStart,
    required this.compactPlainTextStart,
    required this.text,
    required this.textDirection,
    required this.textScale,
    required this.selectionColor,
    required this.registrar,
    required this.selectionRegistry,
    this.atomic = false,
    required super.child,
  });

  final String plainText;
  final int absolutePlainTextStart;
  final int compactPlainTextStart;
  final TextSpan text;
  final TextDirection textDirection;
  final _MarkdownTextScale textScale;
  final Color? selectionColor;
  final SelectionRegistrar? registrar;
  final _MarkdownInlineSelectionRegistry? selectionRegistry;
  final bool atomic;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSelectableInlineTextProxy(
      plainText: plainText,
      absolutePlainTextStart: absolutePlainTextStart,
      compactPlainTextStart: compactPlainTextStart,
      text: text,
      textDirection: textDirection,
      textScale: textScale,
      selectionColor: selectionColor,
      registrar: registrar,
      selectionRegistry: selectionRegistry,
      atomic: atomic,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSelectableInlineTextProxy renderObject,
  ) {
    renderObject
      ..plainText = plainText
      ..absolutePlainTextStart = absolutePlainTextStart
      ..compactPlainTextStart = compactPlainTextStart
      ..text = text
      ..textDirection = textDirection
      ..textScale = textScale
      ..selectionColor = selectionColor
      ..registrar = registrar
      ..selectionRegistry = selectionRegistry
      ..atomic = atomic;
  }
}

/// Marks a real inline widget (image or formula) with the semantic offsets it
/// occupies in the surrounding selectable proxy. The proxy uses the marker's
/// laid-out bounds instead of a synthetic text width when painting selection.
class _MarkdownSelectableAtomicSpan extends SingleChildRenderObjectWidget {
  const _MarkdownSelectableAtomicSpan({
    required this.semanticRange,
    required super.child,
  });

  final TextRange semanticRange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMarkdownSelectableAtomicSpan(semanticRange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMarkdownSelectableAtomicSpan renderObject,
  ) {
    renderObject.semanticRange = semanticRange;
  }
}

abstract interface class _RenderMarkdownSelectableVisualSpan {
  TextRange get semanticRange;
}

class _RenderMarkdownSelectableAtomicSpan extends RenderProxyBox
    implements _RenderMarkdownSelectableVisualSpan {
  _RenderMarkdownSelectableAtomicSpan(this._semanticRange);

  @override
  TextRange get semanticRange => _semanticRange;
  TextRange _semanticRange;
  set semanticRange(TextRange value) {
    if (_semanticRange == value) {
      return;
    }
    _semanticRange = value;
    markNeedsLayout();
  }
}

/// Paints a decorated inline background that can temporarily yield to the
/// coordinator-owned selection surface without rebuilding its widget subtree.
class _MarkdownSelectionAwareBackground extends SingleChildRenderObjectWidget {
  const _MarkdownSelectionAwareBackground({
    required this.text,
    required this.color,
    required this.borderRadius,
    required super.child,
  });

  final String text;
  final Color color;
  final BorderRadius borderRadius;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMarkdownSelectionAwareBackground(
      text: text,
      color: color,
      borderRadius: borderRadius,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMarkdownSelectionAwareBackground renderObject,
  ) {
    renderObject
      ..text = text
      ..color = color
      ..borderRadius = borderRadius;
  }
}

class _RenderMarkdownSelectionAwareBackground extends RenderProxyBox {
  _RenderMarkdownSelectionAwareBackground({
    required String text,
    required Color color,
    required BorderRadius borderRadius,
  })  : _text = text,
        _color = color,
        _borderRadius = borderRadius;

  String get text => _text;
  String _text;
  set text(String value) {
    if (_text == value) {
      return;
    }
    _text = value;
    markNeedsPaint();
  }

  Color get color => _color;
  Color _color;
  set color(Color value) {
    if (_color == value) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  BorderRadius get borderRadius => _borderRadius;
  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) {
      return;
    }
    _borderRadius = value;
    markNeedsPaint();
  }

  TextRange? _selection;
  Color? _selectionColor;

  void applySelection(TextRange? selection, Color? selectionColor) {
    if (_selection == selection && _selectionColor == selectionColor) {
      return;
    }
    _selection = selection;
    _selectionColor = selectionColor;
    markNeedsPaint();
  }

  RenderParagraph? get _renderedParagraph {
    RenderParagraph? result;
    void find(RenderObject object) {
      if (result != null) {
        return;
      }
      object.visitChildren((RenderObject child) {
        if (result != null) {
          return;
        }
        if (child is RenderParagraph && child.text.toPlainText() == text) {
          result = child;
          return;
        }
        find(child);
      });
    }

    find(this);
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final TextRange? selection = _selection;
    final bool fullySelected = selection != null &&
        selection.start <= 0 &&
        selection.end >= text.length;
    if (!fullySelected) {
      context.canvas.drawRRect(
        borderRadius.toRRect(offset & size),
        Paint()..color = color,
      );
    }
    final RenderParagraph? paragraph = _renderedParagraph;
    final Color? activeSelectionColor = _selectionColor;
    if (selection != null &&
        !fullySelected &&
        !selection.isCollapsed &&
        paragraph != null &&
        paragraph.hasSize &&
        activeSelectionColor != null) {
      final Matrix4 transform = paragraph.getTransformTo(this);
      final Paint selectionPaint = Paint()..color = activeSelectionColor;
      for (final TextBox box in paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: selection.start.clamp(0, text.length),
          extentOffset: selection.end.clamp(0, text.length),
        ),
      )) {
        final Rect rect = MatrixUtils.transformRect(transform, box.toRect());
        context.canvas.drawRect(rect.shift(offset), selectionPaint);
      }
    }
    super.paint(context, offset);
  }
}

/// Associates a rendered word with its offsets in the proxy's plain text.
///
/// Animated words are WidgetSpans, so laying the same sentence out in a
/// separate TextPainter is not guaranteed to wrap at the same place. This
/// marker lets selection use the RenderParagraph that actually painted the
/// word while retaining character-level selection inside that word.
class _MarkdownSelectableTextSpan extends SingleChildRenderObjectWidget {
  const _MarkdownSelectableTextSpan({
    required this.semanticRange,
    required this.text,
    this.paintFullSelectionBounds = false,
    this.paintSelectionLocally = false,
    required super.child,
  });

  final TextRange semanticRange;
  final String text;
  final bool paintFullSelectionBounds;
  final bool paintSelectionLocally;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMarkdownSelectableTextSpan(
      semanticRange,
      text,
      paintFullSelectionBounds,
      paintSelectionLocally,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMarkdownSelectableTextSpan renderObject,
  ) {
    renderObject
      ..semanticRange = semanticRange
      ..text = text
      ..paintFullSelectionBounds = paintFullSelectionBounds
      ..paintSelectionLocally = paintSelectionLocally;
  }
}

class _RenderMarkdownSelectableTextSpan extends RenderProxyBox
    implements _RenderMarkdownSelectableVisualSpan {
  _RenderMarkdownSelectableTextSpan(
    this._semanticRange,
    this._text,
    this._paintFullSelectionBounds,
    this._paintSelectionLocally,
  );

  @override
  TextRange get semanticRange => _semanticRange;
  TextRange _semanticRange;
  set semanticRange(TextRange value) {
    if (_semanticRange == value) {
      return;
    }
    _semanticRange = value;
    markNeedsLayout();
  }

  String get text => _text;
  String _text;
  set text(String value) {
    if (_text == value) {
      return;
    }
    _text = value;
    markNeedsLayout();
  }

  bool get paintFullSelectionBounds => _paintFullSelectionBounds;
  bool _paintFullSelectionBounds;
  set paintFullSelectionBounds(bool value) {
    if (_paintFullSelectionBounds == value) {
      return;
    }
    _paintFullSelectionBounds = value;
    markNeedsPaint();
  }

  bool get paintSelectionLocally => _paintSelectionLocally;
  bool _paintSelectionLocally;
  set paintSelectionLocally(bool value) {
    if (_paintSelectionLocally == value) {
      return;
    }
    _paintSelectionLocally = value;
    markNeedsPaint();
  }

  TextRange? _localSelection;
  Color? _localSelectionColor;

  void applyLocalSelection(TextRange? selection, Color? color) {
    if (_localSelection == selection && _localSelectionColor == color) {
      return;
    }
    _localSelection = selection;
    _localSelectionColor = color;
    markNeedsPaint();
  }

  RenderParagraph? get renderedParagraph {
    RenderParagraph? result;
    void find(RenderObject object) {
      if (result != null) {
        return;
      }
      object.visitChildren((RenderObject child) {
        if (result != null) {
          return;
        }
        if (child is RenderParagraph && child.text.toPlainText() == text) {
          result = child;
          return;
        }
        find(child);
      });
    }

    find(this);
    return result;
  }

  RenderEditable? get renderedEditable {
    RenderEditable? result;
    void find(RenderObject object) {
      if (result != null) {
        return;
      }
      object.visitChildren((RenderObject child) {
        if (result != null) {
          return;
        }
        if (child is RenderEditable && child.plainText == text) {
          result = child;
          return;
        }
        find(child);
      });
    }

    find(this);
    return result;
  }

  _RenderMarkdownSelectionAwareBackground? get selectionAwareBackground {
    _RenderMarkdownSelectionAwareBackground? result;
    void find(RenderObject object) {
      if (result != null) {
        return;
      }
      object.visitChildren((RenderObject child) {
        if (result != null) {
          return;
        }
        if (child is _RenderMarkdownSelectionAwareBackground) {
          result = child;
          return;
        }
        find(child);
      });
    }

    find(this);
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final TextRange? selection = _localSelection;
    final Color? color = _localSelectionColor;
    if (paintSelectionLocally &&
        selection != null &&
        !selection.isCollapsed &&
        color != null) {
      final Paint paint = Paint()..color = color;
      final int localStart = selection.start.clamp(0, text.length);
      final int localEnd = selection.end.clamp(localStart, text.length);
      final TextSelection textSelection = TextSelection(
        baseOffset: localStart,
        extentOffset: localEnd,
      );
      final List<Rect> rects;
      final RenderParagraph? paragraph = renderedParagraph;
      final RenderEditable? editable = renderedEditable;
      if (paintFullSelectionBounds &&
          localStart == 0 &&
          localEnd == text.length) {
        rects = <Rect>[Offset.zero & size];
      } else if (paragraph != null && paragraph.hasSize) {
        final Matrix4 transform = paragraph.getTransformTo(this);
        rects = paragraph
            .getBoxesForSelection(textSelection)
            .map(
              (TextBox box) =>
                  MatrixUtils.transformRect(transform, box.toRect()),
            )
            .toList(growable: false);
      } else if (editable != null && editable.hasSize) {
        final Matrix4 transform = editable.getTransformTo(this);
        rects = editable
            .getBoxesForSelection(textSelection)
            .map(
              (TextBox box) =>
                  MatrixUtils.transformRect(transform, box.toRect()),
            )
            .toList(growable: false);
      } else {
        rects = <Rect>[Offset.zero & size];
      }
      for (final Rect rect in rects) {
        context.canvas.drawRect(rect.shift(offset), paint);
      }
    }
    super.paint(context, offset);
  }
}

List<Rect> _mergeMarkdownSelectionRects(Iterable<Rect> input) {
  final List<Rect> rects =
      input.where((Rect rect) => !rect.isEmpty).toList(growable: false)
        ..sort((Rect a, Rect b) {
          final int byTop = a.top.compareTo(b.top);
          return byTop == 0 ? a.left.compareTo(b.left) : byTop;
        });
  final List<Rect> merged = <Rect>[];
  for (final Rect rect in rects) {
    if (merged.isEmpty) {
      merged.add(rect);
      continue;
    }
    final Rect previous = merged.last;
    final double previousCenter = previous.top + previous.height / 2;
    final double rectCenter = rect.top + rect.height / 2;
    final bool sameLine =
        (previousCenter - rectCenter).abs() <= previous.height / 2 + 1;
    if (sameLine) {
      merged[merged.length - 1] = Rect.fromLTRB(
        previous.left < rect.left ? previous.left : rect.left,
        previous.top < rect.top ? previous.top : rect.top,
        previous.right > rect.right ? previous.right : rect.right,
        previous.bottom > rect.bottom ? previous.bottom : rect.bottom,
      );
    } else {
      merged.add(rect);
    }
  }
  return merged;
}

class _RenderSelectableInlineTextProxy extends RenderProxyBox
    implements Selectable {
  _RenderSelectableInlineTextProxy({
    required String plainText,
    required int absolutePlainTextStart,
    required int compactPlainTextStart,
    required TextSpan text,
    required TextDirection textDirection,
    required _MarkdownTextScale textScale,
    required Color? selectionColor,
    required SelectionRegistrar? registrar,
    required _MarkdownInlineSelectionRegistry? selectionRegistry,
    required bool atomic,
  })  : _plainText = plainText,
        _absolutePlainTextStart = absolutePlainTextStart,
        _compactPlainTextStart = compactPlainTextStart,
        _selectionColor = selectionColor,
        _textScale = textScale,
        _registrar = registrar,
        _selectionRegistry = selectionRegistry,
        _atomic = atomic {
    _textPainter
      ..text = text
      ..textDirection = textDirection;
    _applyMarkdownTextScale(_textPainter, textScale);
    _updateSelectionRegistrarSubscription();
  }

  final TextPainter _textPainter = TextPainter();
  final List<VoidCallback> _listeners = <VoidCallback>[];
  final List<_RenderMarkdownSelectableAtomicSpan> _inlineAtomicSpanCache =
      <_RenderMarkdownSelectableAtomicSpan>[];
  final List<_RenderMarkdownSelectableTextSpan> _inlineTextSpanCache =
      <_RenderMarkdownSelectableTextSpan>[];

  String _plainText;
  int _absolutePlainTextStart;
  int _compactPlainTextStart;
  TextSpan get text => _textPainter.text! as TextSpan;
  set text(TextSpan value) {
    if (_textPainter.text == value) {
      return;
    }
    final bool extendsExistingText =
        value.toPlainText().startsWith(text.toPlainText());
    _textPainter.text = value;
    _textPainter.markNeedsLayout();
    if (!extendsExistingText) {
      _clearSelection(notify: false);
    }
    markNeedsLayout();
  }

  String get plainText => _plainText;
  set plainText(String value) {
    if (_plainText == value) {
      return;
    }
    final bool extendsExistingText = value.startsWith(_plainText);
    _plainText = value;
    if (!extendsExistingText) {
      _clearSelection(notify: false);
    }
    _updateSelectionRegistrarSubscription();
    markNeedsLayout();
  }

  int get absolutePlainTextStart => _absolutePlainTextStart;
  set absolutePlainTextStart(int value) {
    if (_absolutePlainTextStart == value) {
      return;
    }
    _absolutePlainTextStart = value;
    _updateSelectionRegistry();
  }

  int get compactPlainTextStart => _compactPlainTextStart;
  set compactPlainTextStart(int value) {
    if (_compactPlainTextStart == value) {
      return;
    }
    _compactPlainTextStart = value;
    _updateSelectionRegistry();
  }

  TextDirection get textDirection => _textPainter.textDirection!;
  set textDirection(TextDirection value) {
    if (_textPainter.textDirection == value) {
      return;
    }
    _textPainter.textDirection = value;
    _textPainter.markNeedsLayout();
    markNeedsLayout();
  }

  _MarkdownTextScale get textScale => _textScale;
  _MarkdownTextScale _textScale;
  set textScale(_MarkdownTextScale value) {
    if (_textScale == value) {
      return;
    }
    _textScale = value;
    _applyMarkdownTextScale(_textPainter, value);
    _textPainter.markNeedsLayout();
    markNeedsLayout();
  }

  Color? get selectionColor => _selectionColor;
  Color? _selectionColor;
  set selectionColor(Color? value) {
    if (_selectionColor == value) {
      return;
    }
    _selectionColor = value;
    if (hasSize) {
      _syncSelectionAwareBackgrounds();
    }
    markNeedsPaint();
  }

  SelectionRegistrar? get registrar => _registrar;
  SelectionRegistrar? _registrar;
  set registrar(SelectionRegistrar? value) {
    if (_registrar == value) {
      return;
    }
    _removeSelectionRegistrarSubscription();
    _registrar = value;
    _updateSelectionRegistrarSubscription();
  }

  _MarkdownInlineSelectionRegistry? get selectionRegistry => _selectionRegistry;
  _MarkdownInlineSelectionRegistry? _selectionRegistry;
  set selectionRegistry(_MarkdownInlineSelectionRegistry? value) {
    if (_selectionRegistry == value) {
      return;
    }
    if (attached) {
      _selectionRegistry?.unregisterSelectable(this);
    }
    _selectionRegistry?.clear(this, notify: false);
    _selectionRegistry = value;
    if (attached) {
      _selectionRegistry?.registerSelectable(this);
    }
    _updateSelectionRegistry();
  }

  bool get atomic => _atomic;
  bool _atomic;
  set atomic(bool value) {
    if (_atomic == value) {
      return;
    }
    _atomic = value;
    markNeedsLayout();
  }

  bool _subscribedToSelectionRegistrar = false;
  int? _selectionStart;
  int? _selectionEnd;
  // Flutter may transiently clear or repartition selection geometry while it
  // moves an edge between selectables. Keep the coordinator-owned paint range
  // independent so those internal transitions cannot produce a blank frame.
  int? _paintSelectionStart;
  int? _paintSelectionEnd;

  // Exposed only through this private render-object type so widget tests can
  // assert paint continuity independently from transient framework geometry.
  TextRange? get debugPaintSelectionRange {
    final int? start = _paintSelectionStart;
    final int? end = _paintSelectionEnd;
    if (start == null || end == null || start == end) {
      return null;
    }
    return TextRange(
      start: start < end ? start : end,
      end: start < end ? end : start,
    );
  }

  List<Rect> get debugPaintSelectionRects =>
      List<Rect>.unmodifiable(_selectionRectsForPaint());

  LayerLink? _startHandleLayerLink;
  LayerLink? _endHandleLayerLink;
  SelectionGeometry _selectionGeometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: false,
  );

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _selectionRegistry?.registerSelectable(this);
    _updateSelectionRegistrarSubscription();
  }

  @override
  void detach() {
    _selectionRegistry?.unregisterSelectable(this);
    _selectionRegistry?.clear(this, notify: false);
    _removeSelectionRegistrarSubscription();
    super.detach();
  }

  @override
  void dispose() {
    _selectionRegistry?.unregisterSelectable(this);
    _selectionRegistry?.clear(this, notify: false);
    _removeSelectionRegistrarSubscription();
    _listeners.clear();
    _textPainter.dispose();
    super.dispose();
  }

  @override
  void performLayout() {
    super.performLayout();
    _refreshInlineAtomicSpans();
    _layoutText();
    _updateSelectionGeometry(
      useVisualSpans: false,
      notifyListeners: false,
    );
    _syncSelectionAwareBackgrounds();
    _updateSelectionRegistrarSubscription();
  }

  void _layoutText() {
    final double maxWidth =
        size.width.isFinite ? size.width : constraints.maxWidth;
    _textPainter.layout(
      maxWidth: maxWidth.isFinite ? maxWidth : double.infinity,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (atomic) {
      super.paint(context, offset);
      _paintSelection(context, offset);
    } else {
      _syncSelectionAwareBackgrounds();
      // Text selection is painted before glyphs, matching RenderParagraph and
      // SelectableText. A fully selected inline decoration yields its own
      // background for this frame, so the line remains one flat surface.
      _paintSelection(context, offset);
      super.paint(context, offset);
      // Opaque non-text spans still need a foreground tint.
      _paintSelectedAtomicSpans(context, offset);
    }
    _pushHandleLayer(
      context,
      offset,
      _startHandleLayerLink,
      _selectionGeometry.startSelectionPoint,
    );
    _pushHandleLayer(
      context,
      offset,
      _endHandleLayerLink,
      _selectionGeometry.endSelectionPoint,
    );
  }

  void _syncSelectionAwareBackgrounds() {
    final int? start = _paintSelectionStart;
    final int? end = _paintSelectionEnd;
    final int rangeStart = start == null || end == null
        ? 0
        : (start < end ? start : end).clamp(0, plainText.length);
    final int rangeEnd = start == null || end == null
        ? 0
        : (start < end ? end : start).clamp(rangeStart, plainText.length);
    for (final _RenderMarkdownSelectableTextSpan span in _inlineTextSpanCache) {
      final int selectedStart = rangeStart > span.semanticRange.start
          ? rangeStart
          : span.semanticRange.start;
      final int selectedEnd =
          rangeEnd < span.semanticRange.end ? rangeEnd : span.semanticRange.end;
      span.applyLocalSelection(
        span.paintSelectionLocally && selectedStart < selectedEnd
            ? TextRange(
                start: selectedStart - span.semanticRange.start,
                end: selectedEnd - span.semanticRange.start,
              )
            : null,
        selectionColor,
      );
      final _RenderMarkdownSelectionAwareBackground? background =
          span.selectionAwareBackground;
      if (background == null) {
        continue;
      }
      background.applySelection(
        selectedStart < selectedEnd
            ? TextRange(
                start: selectedStart - span.semanticRange.start,
                end: selectedEnd - span.semanticRange.start,
              )
            : null,
        selectionColor,
      );
    }
  }

  void _paintSelectedAtomicSpans(PaintingContext context, Offset offset) {
    final int? start = _paintSelectionStart;
    final int? end = _paintSelectionEnd;
    final Color? color = selectionColor;
    if (start == null || end == null || start == end || color == null) {
      return;
    }
    final int rangeStart =
        (start < end ? start : end).clamp(0, plainText.length);
    final int rangeEnd =
        (start < end ? end : start).clamp(rangeStart, plainText.length);
    final Paint paint = Paint()..color = color;
    for (final _RenderMarkdownSelectableAtomicSpan span
        in _inlineAtomicSpanCache) {
      if (span.semanticRange.end <= rangeStart ||
          span.semanticRange.start >= rangeEnd) {
        continue;
      }
      context.canvas.drawRect(_atomicSpanRect(span).shift(offset), paint);
    }
  }

  void _paintSelection(PaintingContext context, Offset offset) {
    final int? start = _paintSelectionStart;
    final int? end = _paintSelectionEnd;
    final Color? color = selectionColor;
    if (start == null ||
        end == null ||
        start == end ||
        color == null ||
        plainText.isEmpty) {
      return;
    }
    final int rangeStart =
        (start < end ? start : end).clamp(0, plainText.length);
    final int rangeEnd =
        (start < end ? end : start).clamp(rangeStart, plainText.length);
    if (rangeStart >= rangeEnd) {
      return;
    }
    if (atomic) {
      context.canvas.drawRect(offset & size, Paint()..color = color);
      return;
    }
    if (_textPainter.width == 0 && hasSize) {
      _layoutText();
    }
    final List<Rect> selectionRects = _selectionRectsForPaint(
      includeLocallyPaintedSpans: false,
    );
    if (selectionRects.isEmpty) {
      return;
    }
    final Paint paint = Paint()..color = color;
    for (final Rect rect in selectionRects) {
      context.canvas.drawRect(rect.shift(offset), paint);
    }
  }

  List<Rect> _selectionRectsForPaint({
    bool includeLocallyPaintedSpans = true,
  }) {
    final int? start = _paintSelectionStart;
    final int? end = _paintSelectionEnd;
    if (start == null || end == null || start == end || plainText.isEmpty) {
      return const <Rect>[];
    }
    final int rangeStart =
        (start < end ? start : end).clamp(0, plainText.length);
    final int rangeEnd =
        (start < end ? end : start).clamp(rangeStart, plainText.length);
    if (rangeStart >= rangeEnd) {
      return const <Rect>[];
    }

    final List<Rect> selectionRects = <Rect>[];
    final List<_RenderMarkdownSelectableVisualSpan> visualSpans =
        <_RenderMarkdownSelectableVisualSpan>[
      ..._inlineTextSpanCache,
      ..._inlineAtomicSpanCache,
    ]..sort(
            (_RenderMarkdownSelectableVisualSpan a,
                    _RenderMarkdownSelectableVisualSpan b) =>
                a.semanticRange.start.compareTo(b.semanticRange.start),
          );
    int textCursor = rangeStart;
    for (final _RenderMarkdownSelectableVisualSpan span in visualSpans) {
      final int spanStart = span.semanticRange.start.clamp(0, plainText.length);
      final int spanEnd =
          span.semanticRange.end.clamp(spanStart, plainText.length);
      if (spanEnd <= rangeStart || spanStart >= rangeEnd) {
        continue;
      }
      final int gapEnd = spanStart.clamp(textCursor, rangeEnd);
      if (textCursor < gapEnd &&
          plainText.substring(textCursor, gapEnd).trim().isNotEmpty) {
        selectionRects.addAll(_semanticSelectionRects(textCursor, gapEnd));
      }
      final int selectedStart = rangeStart > spanStart ? rangeStart : spanStart;
      final int selectedEnd = rangeEnd < spanEnd ? rangeEnd : spanEnd;
      if (selectedStart < selectedEnd) {
        if (span is _RenderMarkdownSelectableTextSpan) {
          if (includeLocallyPaintedSpans || !span.paintSelectionLocally) {
            selectionRects.addAll(
              _textSpanSelectionRects(span, selectedStart, selectedEnd),
            );
          }
        } else if (span is _RenderMarkdownSelectableAtomicSpan) {
          selectionRects.add(_atomicSpanRect(span));
        }
      }
      if (spanEnd > textCursor) {
        textCursor = spanEnd;
      }
    }
    if (textCursor < rangeEnd) {
      final bool hasVisibleText =
          plainText.substring(textCursor, rangeEnd).trim().isNotEmpty;
      if (hasVisibleText || selectionRects.isEmpty) {
        selectionRects.addAll(_semanticSelectionRects(textCursor, rangeEnd));
      }
    }
    return _mergeMarkdownSelectionRects(selectionRects);
  }

  Iterable<Rect> _semanticSelectionRects(int start, int end) {
    return _textPainter
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .map((TextBox box) => box.toRect());
  }

  void _refreshInlineAtomicSpans() {
    _inlineAtomicSpanCache.clear();
    _inlineTextSpanCache.clear();
    void collect(RenderObject object) {
      object.visitChildren((RenderObject child) {
        if (child is _RenderMarkdownSelectableAtomicSpan && child.hasSize) {
          _inlineAtomicSpanCache.add(child);
        } else if (child is _RenderMarkdownSelectableTextSpan &&
            child.hasSize) {
          _inlineTextSpanCache.add(child);
        }
        collect(child);
      });
    }

    collect(this);
    _inlineAtomicSpanCache.sort(
      (_RenderMarkdownSelectableAtomicSpan a,
              _RenderMarkdownSelectableAtomicSpan b) =>
          a.semanticRange.start.compareTo(b.semanticRange.start),
    );
    _inlineTextSpanCache.sort(
      (_RenderMarkdownSelectableTextSpan a,
              _RenderMarkdownSelectableTextSpan b) =>
          a.semanticRange.start.compareTo(b.semanticRange.start),
    );
  }

  List<Rect> _textSpanSelectionRects(
    _RenderMarkdownSelectableTextSpan span,
    int selectedStart,
    int selectedEnd,
  ) {
    if (span.paintFullSelectionBounds &&
        selectedStart <= span.semanticRange.start &&
        selectedEnd >= span.semanticRange.end) {
      return <Rect>[_textSpanRect(span)];
    }
    final RenderParagraph? paragraph = span.renderedParagraph;
    final int localStart =
        (selectedStart - span.semanticRange.start).clamp(0, span.text.length);
    final int localEnd = (selectedEnd - span.semanticRange.start)
        .clamp(localStart, span.text.length);
    final TextSelection selection = TextSelection(
      baseOffset: localStart,
      extentOffset: localEnd,
    );
    if (paragraph != null && paragraph.hasSize) {
      final Matrix4 transform = paragraph.getTransformTo(this);
      return paragraph
          .getBoxesForSelection(selection)
          .map((TextBox box) =>
              MatrixUtils.transformRect(transform, box.toRect()))
          .toList(growable: false);
    }
    final RenderEditable? editable = span.renderedEditable;
    if (editable != null && editable.hasSize) {
      final Matrix4 transform = editable.getTransformTo(this);
      return editable
          .getBoxesForSelection(selection)
          .map((TextBox box) =>
              MatrixUtils.transformRect(transform, box.toRect()))
          .toList(growable: false);
    }
    return <Rect>[_textSpanRect(span)];
  }

  Rect _textSpanRect(_RenderMarkdownSelectableTextSpan span) {
    return MatrixUtils.transformRect(
      span.getTransformTo(this),
      Offset.zero & span.size,
    );
  }

  Rect _atomicSpanRect(_RenderMarkdownSelectableAtomicSpan span) {
    return MatrixUtils.transformRect(
      span.getTransformTo(this),
      Offset.zero & span.size,
    );
  }

  void _pushHandleLayer(
    PaintingContext context,
    Offset paintOffset,
    LayerLink? link,
    SelectionPoint? point,
  ) {
    if (link == null || point == null) {
      return;
    }
    context.pushLayer(
      LeaderLayer(link: link, offset: paintOffset + point.localPosition),
      (PaintingContext context, Offset offset) {},
      Offset.zero,
    );
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifySelectionListeners() {
    final List<VoidCallback> localListeners = List<VoidCallback>.of(_listeners);
    for (final VoidCallback listener in localListeners) {
      listener();
    }
  }

  @override
  SelectionGeometry get value => _selectionGeometry;

  void _updateSelectionGeometry({
    bool useVisualSpans = true,
    bool notifyListeners = true,
  }) {
    final SelectionGeometry next = _computeSelectionGeometry(
      useVisualSpans: useVisualSpans,
    );
    if (next == _selectionGeometry) {
      return;
    }
    _selectionGeometry = next;
    _updateSelectionRegistry();
    if (notifyListeners) {
      _notifySelectionListeners();
    }
    markNeedsPaint();
  }

  void _updateSelectionRegistry() {
    final _MarkdownInlineSelectionRegistry? registry = _selectionRegistry;
    final int? start = _selectionStart;
    final int? end = _selectionEnd;
    if (registry == null ||
        start == null ||
        end == null ||
        start == end ||
        plainText.isEmpty) {
      registry?.clear(this);
      return;
    }
    final int localStart = (start < end ? start : end).clamp(
      0,
      plainText.length,
    );
    final int localEnd = (start < end ? end : start).clamp(
      localStart,
      plainText.length,
    );
    if (localStart >= localEnd) {
      registry.clear(this);
      return;
    }
    registry.update(
      this,
      displayRange: _MarkdownSelectionRange(
        start: absolutePlainTextStart + localStart,
        end: absolutePlainTextStart + localEnd,
      ),
      compactRange: _MarkdownSelectionRange(
        start: compactPlainTextStart + localStart,
        end: compactPlainTextStart + localEnd,
      ),
    );
  }

  void applyDisplaySelection(TextSelection? selection) {
    final int? oldStart = _selectionStart;
    final int? oldEnd = _selectionEnd;
    final int? oldPaintStart = _paintSelectionStart;
    final int? oldPaintEnd = _paintSelectionEnd;
    if (selection == null || !selection.isValid || selection.isCollapsed) {
      _selectionStart = null;
      _selectionEnd = null;
      _paintSelectionStart = null;
      _paintSelectionEnd = null;
    } else {
      final int selectableStart = absolutePlainTextStart;
      final int selectableEnd = selectableStart + plainText.length;
      final int rangeStart = selection.start;
      final int rangeEnd = selection.end;
      if (rangeEnd <= selectableStart || rangeStart >= selectableEnd) {
        _selectionStart = null;
        _selectionEnd = null;
        _paintSelectionStart = null;
        _paintSelectionEnd = null;
      } else {
        final int localStart =
            (rangeStart - selectableStart).clamp(0, plainText.length);
        final int localEnd =
            (rangeEnd - selectableStart).clamp(0, plainText.length);
        _paintSelectionStart = localStart;
        _paintSelectionEnd = localEnd;
        if (selection.baseOffset > selection.extentOffset &&
            selection.baseOffset >= selectableStart &&
            selection.baseOffset <= selectableEnd &&
            selection.extentOffset >= selectableStart &&
            selection.extentOffset <= selectableEnd) {
          _selectionStart = (selection.baseOffset - selectableStart)
              .clamp(0, plainText.length);
          _selectionEnd = (selection.extentOffset - selectableStart)
              .clamp(0, plainText.length);
        } else {
          _selectionStart = localStart;
          _selectionEnd = localEnd;
        }
      }
    }
    if (hasSize) {
      _syncSelectionAwareBackgrounds();
    }
    if (oldStart != _selectionStart || oldEnd != _selectionEnd) {
      if (hasSize) {
        _layoutText();
        _updateSelectionGeometry();
      } else {
        markNeedsLayout();
      }
    } else if (oldPaintStart != _paintSelectionStart ||
        oldPaintEnd != _paintSelectionEnd) {
      markNeedsPaint();
    }
  }

  void clearFrameworkSelectionGeometry() {
    if (_selectionStart == null && _selectionEnd == null) {
      return;
    }
    _selectionStart = null;
    _selectionEnd = null;
    if (hasSize) {
      _updateSelectionGeometry();
    } else {
      markNeedsLayout();
    }
  }

  Rect caretRectForDisplayOffset(int displayOffset) {
    if (atomic) {
      final int localOffset =
          (displayOffset - absolutePlainTextStart).clamp(0, plainText.length);
      final bool atEnd = localOffset > plainText.length ~/ 2;
      final double x =
          atEnd == (textDirection == TextDirection.ltr) ? size.width : 0;
      return Rect.fromLTWH(x, 0, 1, size.height);
    }
    if (_textPainter.width == 0 && hasSize) {
      _layoutText();
    }
    final int localOffset =
        (displayOffset - absolutePlainTextStart).clamp(0, plainText.length);
    return _caretRect(localOffset);
  }

  SelectionGeometry _computeSelectionGeometry({bool useVisualSpans = true}) {
    final int? start = _selectionStart;
    final int? end = _selectionEnd;
    if (plainText.isEmpty || start == null || end == null) {
      return SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: plainText.isNotEmpty,
      );
    }

    final bool collapsed = start == end;
    final bool reversed = start > end;
    final int base = start.clamp(0, plainText.length);
    final int extent = end.clamp(0, plainText.length);
    final Rect startCaret = _caretRect(base, useVisualSpans: useVisualSpans);
    final Rect endCaret = _caretRect(extent, useVisualSpans: useVisualSpans);
    final bool flipHandles = reversed != (textDirection == TextDirection.rtl);
    final TextSelectionHandleType startHandleType;
    final TextSelectionHandleType endHandleType;
    if (collapsed) {
      startHandleType = TextSelectionHandleType.collapsed;
      endHandleType = TextSelectionHandleType.collapsed;
    } else if (flipHandles) {
      startHandleType = TextSelectionHandleType.right;
      endHandleType = TextSelectionHandleType.left;
    } else {
      startHandleType = TextSelectionHandleType.left;
      endHandleType = TextSelectionHandleType.right;
    }
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: startCaret.topLeft,
        lineHeight: startCaret.height,
        handleType: startHandleType,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: endCaret.topLeft,
        lineHeight: endCaret.height,
        handleType: endHandleType,
      ),
      status:
          collapsed ? SelectionStatus.collapsed : SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  Rect _caretRect(int offset, {bool useVisualSpans = true}) {
    if (atomic) {
      final bool atEnd = offset > plainText.length ~/ 2;
      final double x =
          atEnd == (textDirection == TextDirection.ltr) ? size.width : 0;
      return Rect.fromLTWH(x, 0, 1, size.height);
    }
    final int resolvedOffset = offset.clamp(0, plainText.length);
    for (final _RenderMarkdownSelectableTextSpan span in useVisualSpans
        ? _inlineTextSpanCache
        : const <_RenderMarkdownSelectableTextSpan>[]) {
      if (resolvedOffset < span.semanticRange.start ||
          resolvedOffset > span.semanticRange.end) {
        continue;
      }
      final int localOffset = (resolvedOffset - span.semanticRange.start).clamp(
        0,
        span.text.length,
      );
      final RenderEditable? editable = span.renderedEditable;
      if (editable != null && editable.hasSize) {
        return MatrixUtils.transformRect(
          editable.getTransformTo(this),
          editable.getLocalRectForCaret(TextPosition(offset: localOffset)),
        );
      }
      final RenderParagraph? paragraph = span.renderedParagraph;
      if (paragraph != null && paragraph.hasSize) {
        final Offset caret = paragraph.getOffsetForCaret(
          TextPosition(offset: localOffset),
          Rect.zero,
        );
        final int boxStart = span.text.isEmpty
            ? 0
            : (localOffset == span.text.length ? localOffset - 1 : localOffset);
        final int boxEnd = span.text.isEmpty ? 0 : boxStart + 1;
        final List<TextBox> boxes = boxStart < boxEnd
            ? paragraph.getBoxesForSelection(
                TextSelection(baseOffset: boxStart, extentOffset: boxEnd),
              )
            : const <TextBox>[];
        final Rect glyphRect = boxes.isEmpty
            ? Rect.fromLTWH(
                caret.dx,
                caret.dy,
                1,
                _textPainter.preferredLineHeight,
              )
            : Rect.fromLTWH(
                caret.dx,
                boxes.first.top,
                1,
                boxes.first.bottom - boxes.first.top,
              );
        return MatrixUtils.transformRect(
          paragraph.getTransformTo(this),
          glyphRect,
        );
      }
    }
    final Offset caret = _textPainter.getOffsetForCaret(
      TextPosition(offset: resolvedOffset),
      Rect.fromLTWH(0, 0, 1, _textPainter.preferredLineHeight),
    );
    return Rect.fromLTWH(
      caret.dx,
      caret.dy,
      1,
      _textPainter.preferredLineHeight,
    );
  }

  @override
  SelectedContent? getSelectedContent() {
    final int? start = _selectionStart;
    final int? end = _selectionEnd;
    if (start == null || end == null || start == end || plainText.isEmpty) {
      return null;
    }
    final int rangeStart = start < end ? start : end;
    final int rangeEnd = start < end ? end : start;
    return SelectedContent(
      plainText: plainText.substring(
        rangeStart.clamp(0, plainText.length),
        rangeEnd.clamp(0, plainText.length),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // `SelectionHandler.getSelection` was added after Flutter 3.10. Returning
    // null through a noSuchMethod forwarder keeps this selectable source-
    // compatible with both interface revisions.
    if (invocation.memberName == #getSelection) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final int? oldStart = _selectionStart;
    final int? oldEnd = _selectionEnd;
    late SelectionResult result;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        if (_selectionRegistry?.shouldIgnoreFrameworkEdgeUpdate?.call() ??
            false) {
          _clearSelection(notify: false);
          result = SelectionResult.none;
          break;
        }
        final SelectionEdgeUpdateEvent edgeEvent =
            event as SelectionEdgeUpdateEvent;
        final int offset = _positionForLocalOffset(
          globalToLocal(edgeEvent.globalPosition),
        );
        _selectionRegistry?.reportDragUpdate(
          _MarkdownInlineSelectionDragUpdate(
            globalPosition: edgeEvent.globalPosition,
            displayOffset: absolutePlainTextStart + offset,
            compactOffset: compactPlainTextStart + offset,
            isEnd: event.type == SelectionEventType.endEdgeUpdate,
          ),
        );
        result = _updateSelectionEdge(
          edgeEvent.globalPosition,
          isEnd: event.type == SelectionEventType.endEdgeUpdate,
        );
        result = _selectionRegistry?.resolveSelectionResult(result) ?? result;
      case SelectionEventType.clear:
        _clearSelection(notify: false);
        result = SelectionResult.none;
      case SelectionEventType.selectAll:
        _selectionStart = 0;
        _selectionEnd = plainText.length;
        result = SelectionResult.none;
      case SelectionEventType.selectWord:
        _selectionRegistry?.reportDiscreteSelection();
        final SelectWordSelectionEvent wordEvent =
            event as SelectWordSelectionEvent;
        result = _selectWord(wordEvent.globalPosition);
      case SelectionEventType.granularlyExtendSelection:
        final GranularlyExtendSelectionEvent extendEvent =
            event as GranularlyExtendSelectionEvent;
        result = _extendSelection(
          forward: extendEvent.forward,
          isEnd: extendEvent.isEnd,
          granularity: extendEvent.granularity,
        );
      case SelectionEventType.directionallyExtendSelection:
        final DirectionallyExtendSelectionEvent extendEvent =
            event as DirectionallyExtendSelectionEvent;
        result = _extendSelectionDirectionally(extendEvent);
      default:
        _selectionRegistry?.reportDiscreteSelection();
        _selectionStart = 0;
        _selectionEnd = plainText.length;
        result = SelectionResult.end;
    }
    if (oldStart != _selectionStart || oldEnd != _selectionEnd) {
      _updateSelectionGeometry();
    }
    return result;
  }

  SelectionResult _updateSelectionEdge(Offset globalPosition,
      {required bool isEnd}) {
    final Offset localPosition = globalToLocal(globalPosition);
    final int offset = _positionForLocalOffset(localPosition);
    if (isEnd) {
      _selectionEnd = offset;
    } else {
      _selectionStart = offset;
    }
    return _selectionResultForLocalPosition(localPosition);
  }

  int _positionForLocalOffset(Offset localPosition) {
    if (atomic) {
      final bool afterCenter = localPosition.dx >= size.width / 2;
      final bool atEnd =
          textDirection == TextDirection.ltr ? afterCenter : !afterCenter;
      return atEnd ? plainText.length : 0;
    }
    for (final _RenderMarkdownSelectableTextSpan span in _inlineTextSpanCache) {
      final Rect rect = _textSpanRect(span);
      final Rect hitRect = Rect.fromLTRB(
        rect.left,
        rect.top - 2,
        rect.right,
        rect.bottom + 2,
      );
      if (!hitRect.contains(localPosition)) {
        continue;
      }
      final RenderParagraph? paragraph = span.renderedParagraph;
      final RenderEditable? editable = span.renderedEditable;
      if ((paragraph == null || !paragraph.hasSize) &&
          (editable == null || !editable.hasSize)) {
        final bool afterCenter = localPosition.dx >= rect.center.dx;
        final bool atEnd =
            textDirection == TextDirection.ltr ? afterCenter : !afterCenter;
        return atEnd ? span.semanticRange.end : span.semanticRange.start;
      }
      if (editable != null && editable.hasSize) {
        final int characterOffset = editable
            .getPositionForPoint(localToGlobal(localPosition))
            .offset
            .clamp(0, span.text.length);
        return (span.semanticRange.start + characterOffset).clamp(
          span.semanticRange.start,
          span.semanticRange.end,
        );
      }
      final RenderParagraph resolvedParagraph = paragraph!;
      final Offset paragraphPosition = resolvedParagraph.globalToLocal(
        localToGlobal(localPosition),
      );
      final Offset adjusted = SelectionUtils.adjustDragOffset(
        Offset.zero & resolvedParagraph.size,
        paragraphPosition,
        direction: textDirection,
      );
      final int characterOffset = resolvedParagraph
          .getPositionForOffset(adjusted)
          .offset
          .clamp(0, span.text.length);
      return (span.semanticRange.start + characterOffset).clamp(
        span.semanticRange.start,
        span.semanticRange.end,
      );
    }
    for (final _RenderMarkdownSelectableAtomicSpan span
        in _inlineAtomicSpanCache) {
      final Rect rect = _atomicSpanRect(span);
      final Rect hitRect = Rect.fromLTRB(
        rect.left,
        rect.top - 2,
        rect.right,
        rect.bottom + 2,
      );
      if (!hitRect.contains(localPosition)) {
        continue;
      }
      final bool afterCenter = localPosition.dx >= rect.center.dx;
      final bool atEnd =
          textDirection == TextDirection.ltr ? afterCenter : !afterCenter;
      return atEnd ? span.semanticRange.end : span.semanticRange.start;
    }
    final int? visualGapOffset = _positionForVisualGap(localPosition);
    if (visualGapOffset != null) {
      return visualGapOffset;
    }
    final Offset adjusted = SelectionUtils.adjustDragOffset(
      Offset.zero & size,
      localPosition,
      direction: textDirection,
    );
    final TextPosition position = _textPainter.getPositionForOffset(adjusted);
    return position.offset.clamp(0, plainText.length);
  }

  int? _positionForVisualGap(Offset localPosition) {
    final List<({Rect rect, TextRange range})> visualSpans =
        <({Rect rect, TextRange range})>[
      for (final _RenderMarkdownSelectableTextSpan span in _inlineTextSpanCache)
        if (span.hasSize)
          (rect: _textSpanRect(span), range: span.semanticRange),
      for (final _RenderMarkdownSelectableAtomicSpan span
          in _inlineAtomicSpanCache)
        if (span.hasSize)
          (rect: _atomicSpanRect(span), range: span.semanticRange),
    ].where((({Rect rect, TextRange range}) span) {
      return localPosition.dy >= span.rect.top - 2 &&
          localPosition.dy <= span.rect.bottom + 2;
    }).toList(growable: false)
          ..sort(
            (
              ({Rect rect, TextRange range}) a,
              ({Rect rect, TextRange range}) b,
            ) =>
                a.rect.left.compareTo(b.rect.left),
          );
    if (visualSpans.length < 2) {
      return null;
    }
    for (int i = 0; i < visualSpans.length - 1; i++) {
      final ({Rect rect, TextRange range}) left = visualSpans[i];
      final ({Rect rect, TextRange range}) right = visualSpans[i + 1];
      final double gapStart = left.rect.right;
      final double gapEnd = right.rect.left;
      if (gapEnd <= gapStart ||
          localPosition.dx < gapStart ||
          localPosition.dx > gapEnd) {
        continue;
      }
      final int leftOffset = textDirection == TextDirection.ltr
          ? left.range.end
          : left.range.start;
      final int rightOffset = textDirection == TextDirection.ltr
          ? right.range.start
          : right.range.end;
      final double fraction =
          ((localPosition.dx - gapStart) / (gapEnd - gapStart)).clamp(
        0.0,
        1.0,
      );
      return (leftOffset + (rightOffset - leftOffset) * fraction)
          .round()
          .clamp(0, plainText.length);
    }
    return null;
  }

  SelectionResult _selectionResultForLocalPosition(Offset localPosition) {
    if (plainText.isEmpty) {
      return SelectionResult.none;
    }
    return SelectionUtils.getResultBasedOnRect(
        Offset.zero & size, localPosition);
  }

  SelectionResult _selectWord(Offset globalPosition) {
    if (atomic) {
      _selectionStart = 0;
      _selectionEnd = plainText.length;
      return _selectionResultForLocalPosition(globalToLocal(globalPosition));
    }
    final Offset localPosition = globalToLocal(globalPosition);
    final int offset = _positionForLocalOffset(localPosition);
    final TextRange word =
        _textPainter.getWordBoundary(TextPosition(offset: offset));
    final int? existingStart = _selectionStart;
    final int? existingEnd = _selectionEnd;
    if (existingStart != null && existingEnd != null) {
      final int rangeStart =
          existingStart < existingEnd ? existingStart : existingEnd;
      final int rangeEnd =
          existingStart < existingEnd ? existingEnd : existingStart;
      if (rangeStart <= word.start && rangeEnd >= word.end) {
        return _selectionResultForLocalPosition(localPosition);
      }
    }
    _selectionStart = word.start.clamp(0, plainText.length);
    _selectionEnd = word.end.clamp(_selectionStart!, plainText.length);
    return _selectionResultForLocalPosition(localPosition);
  }

  SelectionResult _extendSelection({
    required bool forward,
    required bool isEnd,
    required TextGranularity granularity,
  }) {
    final int step = switch (granularity) {
      TextGranularity.word => _wordStep(forward: forward, isEnd: isEnd),
      TextGranularity.document => plainText.length,
      _ => 1,
    };
    final int current = (isEnd ? _selectionEnd : _selectionStart) ??
        (forward ? 0 : plainText.length);
    final int next =
        (current + (forward ? step : -step)).clamp(0, plainText.length);
    if (isEnd) {
      _selectionEnd = next;
      _selectionStart ??= current;
    } else {
      _selectionStart = next;
      _selectionEnd ??= current;
    }
    return SelectionResult.end;
  }

  int _wordStep({required bool forward, required bool isEnd}) {
    final int current = (isEnd ? _selectionEnd : _selectionStart) ??
        (forward ? 0 : plainText.length);
    final TextRange word =
        _textPainter.getWordBoundary(TextPosition(offset: current));
    if (forward) {
      return (word.end - current).clamp(1, plainText.length);
    }
    return (current - word.start).clamp(1, plainText.length);
  }

  SelectionResult _extendSelectionDirectionally(
    DirectionallyExtendSelectionEvent event,
  ) {
    switch (event.direction) {
      case SelectionExtendDirection.forward:
      case SelectionExtendDirection.nextLine:
        return _extendSelection(
          forward: true,
          isEnd: event.isEnd,
          granularity: TextGranularity.character,
        );
      case SelectionExtendDirection.backward:
      case SelectionExtendDirection.previousLine:
        return _extendSelection(
          forward: false,
          isEnd: event.isEnd,
          granularity: TextGranularity.character,
        );
    }
  }

  void _clearSelection({required bool notify}) {
    _selectionStart = null;
    _selectionEnd = null;
    _selectionRegistry?.clear(this);
    if (notify) {
      _updateSelectionGeometry();
    }
  }

  // Flutter 3.10's Selectable interface does not declare this newer member.
  // ignore: annotate_overrides
  int get contentLength => plainText.length;

  // Flutter 3.10's Selectable interface does not declare this newer member.
  // ignore: annotate_overrides
  List<Rect> get boundingBoxes {
    if (!hasSize || plainText.isEmpty) {
      return <Rect>[Offset.zero & size];
    }
    if (atomic) {
      return <Rect>[Offset.zero & size];
    }
    final List<TextBox> boxes = _textPainter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plainText.length),
    );
    if (boxes.isEmpty) {
      return <Rect>[Offset.zero & size];
    }
    return boxes.map((TextBox box) => box.toRect()).toList(growable: false);
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandleLayerLink == startHandle &&
        _endHandleLayerLink == endHandle) {
      return;
    }
    _startHandleLayerLink = startHandle;
    _endHandleLayerLink = endHandle;
    if (attached) {
      markNeedsPaint();
    }
  }

  void _updateSelectionRegistrarSubscription() {
    final SelectionRegistrar? activeRegistrar = attached ? _registrar : null;
    final bool shouldRegister = plainText.isNotEmpty && activeRegistrar != null;
    if (_subscribedToSelectionRegistrar && !shouldRegister) {
      _registrar?.remove(this);
      _subscribedToSelectionRegistrar = false;
    } else if (!_subscribedToSelectionRegistrar && shouldRegister) {
      activeRegistrar.add(this);
      _subscribedToSelectionRegistrar = true;
    }
  }

  void _removeSelectionRegistrarSubscription() {
    if (!_subscribedToSelectionRegistrar) {
      return;
    }
    _registrar?.remove(this);
    _subscribedToSelectionRegistrar = false;
  }
}
