import 'dart:ffi';

import 'native_symbols.dart';

/// Returns a pointer to the tree-sitter Markdown [TSLanguage].
Pointer<Void> markdownLanguage() => getMarkdownLanguageNative();

/// Returns a pointer to the tree-sitter Markdown inline [TSLanguage].
Pointer<Void> markdownInlineLanguage() => getMarkdownInlineLanguageNative();
