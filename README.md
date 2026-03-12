# streaming_markdown

Flutter FFI plugin exposing `tree-sitter-markdown` and append-friendly rope buffers.

## What this plugin provides

- Native build integration for Android, iOS, macOS, Linux, and Windows.
- Dart API `markdownLanguage()` returning an opaque pointer to `tree_sitter_markdown()`.
- `RopeString` in Dart for efficient append + substring without rebuilding full text.
- `NativeRopeBuffer` backed by C++ for future high-throughput FFI streaming pipelines.
- `RopeMarkdownParser` and `StreamingMarkdownParser` returning Markdown AST nodes in Dart.
- `TreeSitterMarkdownParser` returning full Tree-sitter syntax tree JSON mapped to Dart nodes.

## Usage

```dart
import 'package:streaming_markdown/streaming_markdown.dart';

final rope = RopeString();
rope.append('Hello');
rope.append(' world');
print(rope.substring(0, 5)); // Hello

final nativeRope = NativeRopeBuffer.create();
nativeRope.append('chunk-1');
nativeRope.append('chunk-2');
final tail = nativeRope.substring(7); // chunk-2
nativeRope.dispose();
```

For `NativeRopeBuffer`, substring indices are UTF-8 byte offsets.

## Flutter Example

A visual Flutter demo is available in [example/README.md](example/README.md).
It loads GitHub's `cmark-gfm` spec file and lets you append markdown chunks,
re-parse, and inspect parsed node structures on-screen.
