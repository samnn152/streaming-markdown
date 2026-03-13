import 'dart:ffi';
import 'dart:io';

const String streamingMarkdownLibraryName = 'animated_streaming_markdown';

DynamicLibrary? _cachedLibrary;
Object? _libraryLoadError;

DynamicLibrary get streamingMarkdownDylib {
  final DynamicLibrary? library = _cachedLibrary;
  if (library != null) {
    return library;
  }
  if (_libraryLoadError != null) {
    Error.throwWithStackTrace(_libraryLoadError!, StackTrace.current);
  }

  try {
    final DynamicLibrary library = _openNativeLibrary();
    _cachedLibrary = library;
    return library;
  } catch (error) {
    _libraryLoadError = error;
    rethrow;
  }
}

bool get isStreamingMarkdownNativeLibraryAvailable {
  try {
    streamingMarkdownDylib;
    return true;
  } catch (_) {
    return false;
  }
}

DynamicLibrary _openNativeLibrary() {
  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isMacOS) {
    final List<String> candidates = <String>[
      '$streamingMarkdownLibraryName.framework/$streamingMarkdownLibraryName',
      'lib$streamingMarkdownLibraryName.dylib',
      '$streamingMarkdownLibraryName.dylib',
    ];
    return _openFirstAvailable(candidates);
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$streamingMarkdownLibraryName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$streamingMarkdownLibraryName.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

DynamicLibrary _openFirstAvailable(List<String> candidates) {
  Object? lastError;
  for (final String candidate in candidates) {
    try {
      return DynamicLibrary.open(candidate);
    } catch (error) {
      lastError = error;
    }
  }
  if (lastError != null) {
    throw ArgumentError(lastError.toString());
  }
  throw StateError('No dynamic library candidate provided');
}

typedef _NativeGetMarkdownLanguage = Pointer<Void> Function();

final Pointer<Void> Function() getMarkdownLanguageNative =
    streamingMarkdownDylib
        .lookupFunction<_NativeGetMarkdownLanguage, Pointer<Void> Function()>(
  'streaming_markdown_tree_sitter_markdown',
);

final Pointer<Void> Function() getMarkdownInlineLanguageNative =
    streamingMarkdownDylib
        .lookupFunction<_NativeGetMarkdownLanguage, Pointer<Void> Function()>(
  'streaming_markdown_tree_sitter_markdown_inline',
);
