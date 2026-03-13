import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_symbols.dart';

/// Native incremental markdown parser session.
///
/// This parser keeps native parse state so append operations can be processed
/// incrementally instead of reparsing from scratch.
class NativeIncrementalMarkdownParser implements Finalizable {
  static const int _defaultMaxNodes = 0x7fffffff;
  static final NativeFinalizer _finalizer = NativeFinalizer(
    _destroySymbol.cast(),
  );

  final Pointer<Void> _handle;
  bool _disposed = false;

  NativeIncrementalMarkdownParser._(this._handle) {
    _finalizer.attach(this, _handle, detach: this);
  }

  /// Creates a new incremental parser session.
  ///
  /// Throws [StateError] when the native library is unavailable.
  factory NativeIncrementalMarkdownParser.create() {
    if (!isStreamingMarkdownNativeLibraryAvailable) {
      throw StateError(
        'Native animated_streaming_markdown library is unavailable',
      );
    }

    final Pointer<Void> handle = _createSession();
    if (handle == nullptr) {
      throw StateError('Unable to create incremental parser session');
    }
    return NativeIncrementalMarkdownParser._(handle);
  }

  /// Replaces the full source text and reparses.
  bool setText(String text) {
    _ensureNotDisposed();
    final Pointer<Utf8> nativeText = text.toNativeUtf8();
    try {
      return _setText(_handle, nativeText) != 0;
    } finally {
      malloc.free(nativeText);
    }
  }

  /// Appends a text chunk and reparses incrementally.
  bool appendText(String text) {
    _ensureNotDisposed();
    if (text.isEmpty) {
      return true;
    }
    final Pointer<Utf8> nativeText = text.toNativeUtf8();
    try {
      return _appendText(_handle, nativeText) != 0;
    } finally {
      malloc.free(nativeText);
    }
  }

  /// Returns the current block-node count from native tree-sitter output.
  int blockCount() {
    _ensureNotDisposed();
    return _blockCount(_handle);
  }

  /// Returns how many inline node types have been observed.
  int inlineTypeCount() {
    _ensureNotDisposed();
    return _inlineTypeCount(_handle);
  }

  /// Returns flattened block nodes as decoded JSON maps.
  List<Map<String, Object>> blockNodes({int? maxNodes}) {
    _ensureNotDisposed();
    final int resolvedMaxNodes = maxNodes ?? _defaultMaxNodes;
    if (resolvedMaxNodes <= 0) {
      return <Map<String, Object>>[];
    }

    final Pointer<Utf8> nativeJson = _blockNodesJson(_handle, resolvedMaxNodes);
    if (nativeJson == nullptr) {
      throw StateError('Native block node JSON generation failed');
    }

    try {
      final Object? decoded = jsonDecode(nativeJson.toDartString());
      if (decoded is! List<dynamic>) {
        return <Map<String, Object>>[];
      }

      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> raw) {
        return <String, Object>{
          'type': (raw['type'] as String?) ?? 'unknown',
          'depth': _asInt(raw['depth']),
          'startByte': _asInt(raw['startByte']),
          'endByte': _asInt(raw['endByte']),
          'startRow': _asInt(raw['startRow']),
          'endRow': _asInt(raw['endRow']),
          'raw': (raw['raw'] as String?) ?? '',
        };
      }).toList(growable: false);
    } finally {
      _freeCString(nativeJson);
    }
  }

  /// Disposes the native parser session.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _finalizer.detach(this);
    _destroySession(_handle);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('NativeIncrementalMarkdownParser has been disposed');
    }
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _destroySymbol =
    streamingMarkdownDylib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
  'streaming_markdown_incremental_destroy',
);

final Pointer<Void> Function() _createSession = streamingMarkdownDylib
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
  'streaming_markdown_incremental_create',
);

final void Function(Pointer<Void>) _destroySession = streamingMarkdownDylib
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
  'streaming_markdown_incremental_destroy',
);

final int Function(Pointer<Void>, Pointer<Utf8>) _setText =
    streamingMarkdownDylib.lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>,
            Pointer<Utf8>)>('streaming_markdown_incremental_set_text');

final int Function(Pointer<Void>, Pointer<Utf8>) _appendText =
    streamingMarkdownDylib.lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Utf8>),
        int Function(Pointer<Void>,
            Pointer<Utf8>)>('streaming_markdown_incremental_append_text');

final int Function(Pointer<Void>) _blockCount =
    streamingMarkdownDylib.lookupFunction<
        Uint32 Function(Pointer<Void>),
        int Function(
            Pointer<Void>)>('streaming_markdown_incremental_block_count');

final int Function(Pointer<Void>) _inlineTypeCount =
    streamingMarkdownDylib.lookupFunction<
        Uint32 Function(Pointer<Void>),
        int Function(
            Pointer<Void>)>('streaming_markdown_incremental_inline_type_count');

final Pointer<Utf8> Function(Pointer<Void>, int) _blockNodesJson =
    streamingMarkdownDylib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Uint32),
        Pointer<Utf8> Function(Pointer<Void>,
            int)>('streaming_markdown_incremental_block_nodes_json');

final void Function(Pointer<Utf8>) _freeCString = streamingMarkdownDylib
    .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
  'streaming_markdown_rope_free_c_string',
);
