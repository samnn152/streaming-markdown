part of '../view.dart';

class _SelectableInlineTextOverlay extends StatefulWidget {
  const _SelectableInlineTextOverlay({
    required this.tokens,
    required this.baseStyle,
    required this.footnoteNumbers,
    required this.textScaler,
    required this.selectionColor,
    required this.onLinkTap,
  });

  final List<_InlineToken> tokens;
  final TextStyle baseStyle;
  final Map<String, int> footnoteNumbers;
  final TextScaler textScaler;
  final Color selectionColor;
  final ValueChanged<String> onLinkTap;

  @override
  State<_SelectableInlineTextOverlay> createState() =>
      _SelectableInlineTextOverlayState();
}

class _SelectableInlineTextOverlayState
    extends State<_SelectableInlineTextOverlay> {
  List<TapGestureRecognizer?> _linkRecognizers = <TapGestureRecognizer?>[];

  @override
  void initState() {
    super.initState();
    _replaceRecognizers();
  }

  @override
  void didUpdateWidget(covariant _SelectableInlineTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _replaceRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _replaceRecognizers() {
    _disposeRecognizers();
    _linkRecognizers = widget.tokens.map((token) {
      final String? url = token.linkUrl;
      if (url == null || url.isEmpty) {
        return null;
      }
      return TapGestureRecognizer()
        ..onTap = () {
          widget.onLinkTap(url);
        };
    }).toList(growable: false);
  }

  void _disposeRecognizers() {
    for (final TapGestureRecognizer? recognizer in _linkRecognizers) {
      recognizer?.dispose();
    }
    _linkRecognizers = <TapGestureRecognizer?>[];
  }

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = 0; i < widget.tokens.length; i++) {
      final _InlineToken token = widget.tokens[i];
      if (token.isImage) {
        final String imageText =
            token.altText.isEmpty ? '[image]' : '[image: ${token.altText}]';
        spans.add(
          TextSpan(
            text: imageText,
            style: _selectionOverlayStyle(
              widget.baseStyle.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        );
        continue;
      }

      if (token.isFootnoteReference) {
        final int? footnoteNumber = _footnoteNumberForId(
          widget.footnoteNumbers,
          token.footnoteReferenceId!,
        );
        final String label =
            footnoteNumber?.toString() ?? token.footnoteReferenceId!;
        spans.add(
          TextSpan(
            text: label,
            style: _selectionOverlayStyle(
              widget.baseStyle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        continue;
      }

      TextStyle style = widget.baseStyle;
      if (token.style.bold) {
        style = style.copyWith(fontWeight: FontWeight.w700);
      }
      if (token.style.italic) {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
      if (token.style.strikethrough) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (token.style.code) {
        style = style.copyWith(fontFamily: 'monospace', fontSize: 12);
      }
      if (token.linkUrl != null && token.linkUrl!.isNotEmpty) {
        style = style.copyWith(decoration: TextDecoration.underline);
      }

      spans.add(
        TextSpan(
          text: token.text,
          style: _selectionOverlayStyle(style),
          recognizer: _linkRecognizers[i],
        ),
      );
    }

    return RichText(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: widget.textScaler,
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor: widget.selectionColor,
      text: TextSpan(style: widget.baseStyle, children: spans),
    );
  }
}

TextStyle _selectionOverlayStyle(TextStyle style) {
  final Paint transparentPaint = Paint()..color = Colors.transparent;
  return style.copyWith(
    decorationColor: Colors.transparent,
    shadows: const <Shadow>[],
    foreground: transparentPaint,
    background: transparentPaint,
  );
}
