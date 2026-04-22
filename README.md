# animated_streaming_markdown

`animated_streaming_markdown` is a Flutter package for streaming Markdown
workflows with:

- native tree-sitter parsing (FFI)
- incremental parse sessions for append-heavy updates
- streaming-friendly Flutter rendering (`StreamingMarkdownRenderView`)
- pure-Dart fallback parsing utilities (`RopeString`, `RopeMarkdownParser`)

## Requirements

- Dart SDK: `>=2.17.0 <4.0.0`
- Flutter SDK: `>=3.0.0`
- Runtime targets: Android, iOS, macOS, Linux, Windows
- Web: not supported as a runtime target

### Platform Requirements

- Android: Flutter Android toolchain and Android NDK available for FFI/native build steps.
- iOS: Xcode + CocoaPods toolchain.
- macOS: Xcode + CocoaPods toolchain.
- Linux: Flutter Linux desktop enabled, plus C/C++ desktop build tools (`cmake`, compiler toolchain).
- Windows: Flutter Windows desktop enabled, plus Visual Studio C++ desktop toolchain.
- Web: intentionally unsupported for production runtime use; native APIs are unavailable.

## Installation

Add dependency to `pubspec.yaml`:

```yaml
dependencies:
  animated_streaming_markdown: ^0.1.6
```

Install packages:

```bash
flutter pub get
```

## Usage

### 1. Streaming parse + render in UI

```dart
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';
import 'package:flutter/material.dart';

class StreamingMarkdownPane extends StatefulWidget {
  const StreamingMarkdownPane({super.key});

  @override
  State<StreamingMarkdownPane> createState() => _StreamingMarkdownPaneState();
}

class _StreamingMarkdownPaneState extends State<StreamingMarkdownPane> {
  final StreamingMarkdownParseWorker _worker = StreamingMarkdownParseWorker();
  List<MarkdownRenderNode> _nodes = const <MarkdownRenderNode>[];
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _worker.start();
    setState(() {
      _started = true;
    });
  }

  Future<void> setMarkdown(String text) async {
    if (!_started) return;
    final result = await _worker.request(
      op: 'set',
      text: text,
      includeNodes: true,
    );
    setState(() {
      _nodes = result.renderNodes;
    });
  }

  Future<void> appendMarkdownChunk(String chunk) async {
    if (!_started) return;
    final result = await _worker.request(
      op: 'append',
      text: chunk,
      includeNodes: true,
    );
    setState(() {
      _nodes = result.renderNodes;
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamingMarkdownRenderView(
      nodes: _nodes,
      enableTextSelection: true,
      tokenArrivalDelay: const Duration(milliseconds: 25),
      tokenFadeInDuration: const Duration(milliseconds: 140),
    );
  }
}
```

### 2. Pure-Dart parsing without native APIs

```dart
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';

final RopeString rope = RopeString();
rope.append('# Hello');
rope.append('\n\nParagraph');

final MarkdownDocument doc = const RopeMarkdownParser().parse(rope);
print(doc.blocks.length);
```

### 3. Native parser usage with availability check

```dart
import 'package:animated_streaming_markdown/animated_streaming_markdown.dart';

if (isStreamingMarkdownNativeLibraryAvailable) {
  final parser = NativeIncrementalMarkdownParser.create();
  parser.setText('# Title');
  final count = parser.blockCount();
  parser.dispose();
  print(count);
}
```

## Rendering Notes

- `StreamingMarkdownRenderView` accepts `List<MarkdownRenderNode>` and renders block-by-block.
- HTML block nodes are rendered with pure Flutter widgets (no embedded WebView).
- HTML blocks wrap content height naturally instead of using a fixed viewport.

## Example App

See `example/` for a dual-pane chat demo and end-to-end streaming usage.

## Bundled Tree-sitter Dependencies

This package vendors only the required native sources under `packages/`:

- `packages/tree-sitter` (tree-sitter runtime)
- `packages/tree-sitter-markdown` (block + inline markdown grammars)

Both bundled upstream components are MIT-licensed. This package remains Apache-2.0.

## License

`animated_streaming_markdown` is licensed under Apache License 2.0. See [LICENSE](LICENSE).

Third-party license details are listed in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
