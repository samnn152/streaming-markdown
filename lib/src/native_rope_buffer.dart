import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_symbols.dart';

final class NativeRopeBuffer implements Finalizable {
  static final NativeFinalizer _finalizer = NativeFinalizer(
    _ropeDestroyPtr.cast(),
  );

  final Pointer<Void> _handle;
  bool _disposed = false;

  NativeRopeBuffer._(this._handle) {
    _finalizer.attach(this, _handle, detach: this);
  }

  factory NativeRopeBuffer.create() {
    final Pointer<Void> handle = _ropeCreate();
    if (handle == nullptr) {
      throw StateError('Unable to allocate native rope buffer');
    }
    return NativeRopeBuffer._(handle);
  }

  int get lengthBytes {
    _ensureNotDisposed();
    return _ropeLength(_handle);
  }

  void append(String text) {
    _ensureNotDisposed();
    if (text.isEmpty) return;
    final Pointer<Utf8> nativeText = text.toNativeUtf8();
    try {
      _ropeAppend(_handle, nativeText);
    } finally {
      malloc.free(nativeText);
    }
  }

  String substring(int start, [int? end]) {
    _ensureNotDisposed();
    final int resolvedEnd = end ?? lengthBytes;
    RangeError.checkValidRange(start, resolvedEnd, lengthBytes);
    final Pointer<Utf8> nativeResult = _ropeSubstring(
      _handle,
      start,
      resolvedEnd,
    );
    if (nativeResult == nullptr) {
      throw RangeError(
        'Invalid native substring range: [$start, $resolvedEnd)',
      );
    }

    try {
      return nativeResult.toDartString();
    } finally {
      _ropeFreeCString(nativeResult);
    }
  }

  void clear() {
    _ensureNotDisposed();
    _ropeClear(_handle);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _ropeDestroy(_handle);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('NativeRopeBuffer has been disposed');
    }
  }
}

final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _ropeDestroyPtr =
    streamingMarkdownDylib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'streaming_markdown_rope_destroy',
    );

final Pointer<Void> Function() _ropeCreate = streamingMarkdownDylib
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'streaming_markdown_rope_create',
    );

final void Function(Pointer<Void>) _ropeDestroy = streamingMarkdownDylib
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'streaming_markdown_rope_destroy',
    );

final void Function(Pointer<Void>, Pointer<Utf8>) _ropeAppend =
    streamingMarkdownDylib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Utf8>),
      void Function(Pointer<Void>, Pointer<Utf8>)
    >('streaming_markdown_rope_append_utf8');

final int Function(Pointer<Void>) _ropeLength = streamingMarkdownDylib
    .lookupFunction<
      Uint64 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('streaming_markdown_rope_length_bytes');

final Pointer<Utf8> Function(Pointer<Void>, int, int) _ropeSubstring =
    streamingMarkdownDylib.lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint64, Uint64),
      Pointer<Utf8> Function(Pointer<Void>, int, int)
    >('streaming_markdown_rope_substring_utf8');

final void Function(Pointer<Utf8>) _ropeFreeCString = streamingMarkdownDylib
    .lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
      'streaming_markdown_rope_free_c_string',
    );

final void Function(Pointer<Void>) _ropeClear = streamingMarkdownDylib
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'streaming_markdown_rope_clear',
    );
