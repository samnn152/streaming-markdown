part of '../view.dart';

/// Immutable source-backed selection state for
/// [AnimatedStreamingMarkdown].
@immutable
class AnimatedMarkdownSelectionValue {
  /// Creates a selection value for one Markdown source snapshot.
  const AnimatedMarkdownSelectionValue({
    required this.sourceText,
    required this.selection,
  });

  /// Creates a value with no source text or valid selection.
  const AnimatedMarkdownSelectionValue.empty()
      : sourceText = '',
        selection = const TextSelection.collapsed(offset: -1);

  /// The Markdown source snapshot to which [selection] belongs.
  final String sourceText;

  /// Directional UTF-16 offsets into [sourceText].
  final TextSelection selection;

  /// Whether this value contains a non-collapsed valid selection.
  bool get hasSelection =>
      selection.isValid && !selection.isCollapsed && sourceText.isNotEmpty;

  /// The exact Markdown source selected by [selection].
  String get selectedMarkdown {
    if (!hasSelection) {
      return '';
    }
    final int start = selection.start.clamp(0, sourceText.length);
    final int end = selection.end.clamp(start, sourceText.length);
    return start < end ? sourceText.substring(start, end) : '';
  }

  /// Returns a value with the supplied fields replaced.
  AnimatedMarkdownSelectionValue copyWith({
    String? sourceText,
    TextSelection? selection,
  }) {
    return AnimatedMarkdownSelectionValue(
      sourceText: sourceText ?? this.sourceText,
      selection: selection ?? this.selection,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AnimatedMarkdownSelectionValue &&
        other.sourceText == sourceText &&
        other.selection == selection;
  }

  @override
  int get hashCode => Object.hash(sourceText, selection);
}

/// Controller for observing and changing a Markdown source selection.
///
/// The renderer owns [AnimatedMarkdownSelectionValue.sourceText]. Consumers
/// may set [selection], call [clear], or call [selectAll]. Offsets are clamped
/// to extended grapheme boundaries before they are published.
class AnimatedMarkdownSelectionController extends ChangeNotifier
    implements ValueListenable<AnimatedMarkdownSelectionValue> {
  /// Creates a controller with an optional initial directional selection.
  ///
  /// The offsets are normalized after a renderer supplies its source snapshot.
  AnimatedMarkdownSelectionController({TextSelection? selection})
      : _value = AnimatedMarkdownSelectionValue(
          sourceText: '',
          selection: selection ?? const TextSelection.collapsed(offset: -1),
        );

  AnimatedMarkdownSelectionValue _value;

  @override
  AnimatedMarkdownSelectionValue get value => _value;

  /// Current directional UTF-16 range in [value]'s Markdown source.
  TextSelection get selection => _value.selection;

  /// Changes the source range and asks the renderer to reveal its extent.
  set selection(TextSelection value) {
    _setValue(
      AnimatedMarkdownSelectionValue(
        sourceText: _value.sourceText,
        selection: _normalizeSelection(value, _value.sourceText),
      ),
    );
  }

  /// Clears the current selection without changing the source snapshot.
  void clear() {
    selection = const TextSelection.collapsed(offset: -1);
  }

  /// Selects the complete current Markdown source snapshot.
  void selectAll() {
    selection = TextSelection(
      baseOffset: 0,
      extentOffset: _value.sourceText.length,
    );
  }

  void _updateFromRenderer({
    required String sourceText,
    required TextSelection selection,
  }) {
    _setValue(
      AnimatedMarkdownSelectionValue(
        sourceText: sourceText,
        selection: _normalizeSelection(selection, sourceText),
      ),
    );
  }

  void _synchronizeSourceText(
    String sourceText, {
    TextSelection? remappedSelection,
  }) {
    final TextSelection current = remappedSelection ?? _value.selection;
    _setValue(
      AnimatedMarkdownSelectionValue(
        sourceText: sourceText,
        selection: _normalizeSelection(current, sourceText),
      ),
    );
  }

  void _setValue(AnimatedMarkdownSelectionValue value) {
    if (_value == value) {
      return;
    }
    _value = value;
    notifyListeners();
  }

  static TextSelection _normalizeSelection(
    TextSelection selection,
    String sourceText,
  ) {
    if (!selection.isValid) {
      return const TextSelection.collapsed(offset: -1);
    }
    final int base = _nearestGraphemeBoundary(
      sourceText,
      selection.baseOffset.clamp(0, sourceText.length),
    );
    final int extent = _nearestGraphemeBoundary(
      sourceText,
      selection.extentOffset.clamp(0, sourceText.length),
    );
    return TextSelection(
      baseOffset: base,
      extentOffset: extent,
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  static int _nearestGraphemeBoundary(String text, int offset) {
    if (offset <= 0 || text.isEmpty) {
      return 0;
    }
    if (offset >= text.length) {
      return text.length;
    }
    int previous = 0;
    for (final String grapheme in text.characters) {
      final int next = previous + grapheme.length;
      if (offset <= next) {
        return offset - previous <= next - offset ? previous : next;
      }
      previous = next;
    }
    return text.length;
  }
}
