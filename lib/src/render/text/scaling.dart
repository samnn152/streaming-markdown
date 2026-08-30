part of '../view.dart';

/// SDK-neutral text scaling value.
///
/// Flutter 3.10 only exposes a linear `textScaleFactor`, while newer SDKs
/// expose nonlinear `TextScaler`. Keeping the native value dynamic lets one
/// package artifact preserve nonlinear scaling on new SDKs and still compile
/// against Flutter 3.10.
class _MarkdownTextScale {
  const _MarkdownTextScale({
    required this.nativeScaler,
    required this.linearFactor,
  });

  final dynamic nativeScaler;
  final double linearFactor;

  @override
  bool operator ==(Object other) {
    return other is _MarkdownTextScale &&
        other.nativeScaler == nativeScaler &&
        other.linearFactor == linearFactor;
  }

  @override
  int get hashCode => Object.hash(nativeScaler, linearFactor);
}

_MarkdownTextScale _markdownTextScaleOf(BuildContext context) {
  // ignore: deprecated_member_use
  final double linearFactor = MediaQuery.textScaleFactorOf(context);
  final dynamic mediaQueryData = MediaQuery.of(context);
  dynamic nativeScaler;
  try {
    nativeScaler = mediaQueryData.textScaler;
  } on NoSuchMethodError {
    nativeScaler = null;
  }
  return _MarkdownTextScale(
    nativeScaler: nativeScaler,
    linearFactor: linearFactor,
  );
}

Widget _markdownRichText({
  Key? key,
  required InlineSpan text,
  required TextAlign textAlign,
  required TextDirection textDirection,
  required _MarkdownTextScale textScale,
  SelectionRegistrar? selectionRegistrar,
  Color? selectionColor,
}) {
  final Map<Symbol, dynamic> arguments = <Symbol, dynamic>{
    #key: key,
    #text: text,
    #textAlign: textAlign,
    #textDirection: textDirection,
    #selectionRegistrar: selectionRegistrar,
    #selectionColor: selectionColor,
  };
  final dynamic nativeScaler = textScale.nativeScaler;
  if (nativeScaler != null) {
    arguments[#textScaler] = nativeScaler;
    try {
      return Function.apply(RichText.new, const <dynamic>[], arguments)
          as Widget;
    } on NoSuchMethodError {
      arguments.remove(#textScaler);
    }
  }
  arguments[#textScaleFactor] = textScale.linearFactor;
  return Function.apply(RichText.new, const <dynamic>[], arguments) as Widget;
}

void _applyMarkdownTextScale(
  TextPainter painter,
  _MarkdownTextScale textScale,
) {
  final dynamic dynamicPainter = painter;
  final dynamic nativeScaler = textScale.nativeScaler;
  if (nativeScaler != null) {
    try {
      dynamicPainter.textScaler = nativeScaler;
      return;
    } on NoSuchMethodError {
      // Flutter 3.10 falls through to the linear API below.
    }
  }
  dynamicPainter.textScaleFactor = textScale.linearFactor;
}
