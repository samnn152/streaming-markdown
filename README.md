# animated_streaming_markdown

This package is vibe-coded and currently under active construction.

API surface and behavior may change while streaming and rendering features are being stabilized.

## Overview

`animated_streaming_markdown` is a Flutter FFI package for markdown streaming workflows. It exposes:

- append-friendly rope buffers (`RopeString`, `NativeRopeBuffer`)
- native tree-sitter markdown parsers (`TreeSitterMarkdownParser`)
- native incremental parser sessions (`NativeIncrementalMarkdownParser`)
- isolate-based parsing for UI pipelines (`StreamingMarkdownParseWorker`)
- a streaming-friendly Flutter renderer (`StreamingMarkdownRenderView`)

## Installation

Add dependency:

```yaml
dependencies:
  animated_streaming_markdown: ^0.1.2
```

Then run:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:animated_streaming_markdown/streaming_markdown.dart';

Future<void> parseIncrementally() async {
  final worker = StreamingMarkdownParseWorker();
  await worker.start();

  await worker.request(
    op: 'set',
    text: '# Hello\n\n| A | B |\n| - | - |\n',
    includeNodes: true,
  );

  final result = await worker.request(
    op: 'append',
    text: '| 1 | 2 |\n',
    includeNodes: true,
  );

  // Use result.renderNodes in StreamingMarkdownRenderView.
  print(result.renderNodes.length);

  worker.dispose();
}
```

## Flutter Rendering

```dart
StreamingMarkdownRenderView(
  nodes: renderNodes,
  tokenArrivalDelay: const Duration(milliseconds: 50),
  tokenFadeInDuration: const Duration(milliseconds: 300),
  enableTextSelection: true,
)
```

## Public API Documentation

Public API docs are written as DartDoc comments directly in source files:

- `lib/streaming_markdown.dart` (entrypoint and export guide)
- exported API classes in `lib/src/*`

Use IDE hover/completion docs or `dart doc` to generate HTML docs.

## Example App

See `example/` for a dual-pane chat demo (default theme vs custom theme) with shared question input and streaming markdown rendering.

## Bundled Tree-sitter Dependencies

This package vendors only the required native sources under `packages/`:

- `packages/tree-sitter` (tree-sitter runtime)
- `packages/tree-sitter-markdown` (block + inline markdown grammars)

Both bundled upstream components are MIT-licensed. Current package
(`animated_streaming_markdown`) remains Apache-2.0.

## License

`animated_streaming_markdown` is licensed under Apache License 2.0. See [LICENSE](LICENSE).

Third-party license details are listed in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
