// Modified by animated_streaming_markdown: expose only the view renderer.
// Equation selection is coordinated by the Markdown selection engine.

/// Basic utilities to render math equations.
///
/// Please refer to README for usage.
library flutter_math_fork;

export 'src/ast/options.dart' show MathOptions, FontOptions;
export 'src/ast/size.dart' show MathSize;
export 'src/ast/style.dart' show MathStyle;
export 'src/encoder/exception.dart';
export 'src/parser/tex/parse_error.dart';
export 'src/parser/tex/settings.dart';
export 'src/widgets/exception.dart';
export 'src/widgets/math.dart';
