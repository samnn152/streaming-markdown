# API Overview

`animated_streaming_markdown` has two public layers:

- `MarkdownStreamParser` turns streamed Markdown text into renderable blocks.
- `AnimatedStreamingMarkdown` renders those blocks with token-level animation,
  stable layout, link handling, and optional Markdown-aware selection copy.

The `0.3.x` API names describe those roles directly. The older `0.2.x` names
remain available for migration compatibility.

## Parser

Create one parser per active Markdown stream.

```dart
final parser = MarkdownStreamParser();
await parser.start();
```

Use `replace` when you have a complete document snapshot:

```dart
final result = await parser.replace('# Ready');
```

Use `append` when your source emits only the next chunk:

```dart
final result = await parser.append('\n\nStreaming **Markdown**...');
```

Use `parse` when the operation is selected at runtime:

```dart
final result = await parser.parse(
  operation: MarkdownParseOperation.append,
  text: chunk,
);
```

Dispose the parser when the stream is no longer needed:

```dart
parser.dispose();
```

## Parse Result

`MarkdownParseResult.blocks` is the primary output for rendering:

```dart
final List<MarkdownBlock> blocks = result.blocks;
```

The result also includes parser diagnostics:

- `basicBlockCount`
- `inlineTypeCount`
- `nativeAvailable`
- `mode`
- `includesNodes`
- `updateTime`
- `statsTime`
- `totalTime`

## Renderer

Render parsed blocks with `AnimatedStreamingMarkdown`:

```dart
AnimatedStreamingMarkdown(
  blocks: result.blocks,
  tokenStaggerDelay: const Duration(milliseconds: 120),
  tokenAnimationDuration: const Duration(milliseconds: 220),
  enableSelection: true,
);
```

For sliver layouts:

```dart
CustomScrollView(
  slivers: [
    AnimatedStreamingMarkdown(
      blocks: result.blocks,
      asSliver: true,
    ),
  ],
);
```

## Token Animation

Use `tokenAnimationBuilder` to customize how each token appears:

```dart
AnimatedStreamingMarkdown(
  blocks: result.blocks,
  tokenStaggerDelay: const Duration(milliseconds: 80),
  tokenAnimationDuration: const Duration(milliseconds: 240),
  tokenAnimationBuilder: (context, token) {
    final t = Curves.easeOutCubic.transform(token.value);
    return Transform.translate(
      offset: Offset(0, (1 - t) * 8),
      child: Opacity(opacity: t, child: token.child),
    );
  },
);
```

The timing parameters are:

- `tokenStaggerDelay`: delay between adjacent token starts.
- `tokenAnimationDuration`: duration of each token animation.
- `tokenAnimationDurationFactor`: derives animation duration from
  `tokenStaggerDelay` when `tokenAnimationDuration` is omitted.
- `tokenAnimationCurve`: curve applied to the token animation.
- `onTokenDelay`: called when the renderer is waiting for a delayed token.
- `onTokenAnimationEnd`: called when a token animation finishes.

## Selection Copy

Set `enableSelection` to wrap the renderer in a `SelectionArea` and use
Markdown-aware copy behavior:

```dart
AnimatedStreamingMarkdown(
  blocks: result.blocks,
  enableSelection: true,
);
```

When possible, copied text preserves Markdown source semantics such as links,
tables, code fences, block quotes, and footnote definitions.

## Theming

Use `AnimatedMarkdownThemeData` to override visual styling without replacing the
renderer:

```dart
AnimatedStreamingMarkdown(
  blocks: result.blocks,
  theme: const AnimatedMarkdownThemeData(
    blockSpacing: 16,
    codeBlockBackgroundColor: Color(0xFF0F172A),
  ),
);
```

## Custom Blocks

Use `blockBuilder` to replace or wrap individual rendered blocks:

```dart
AnimatedStreamingMarkdown(
  blocks: result.blocks,
  blockBuilder: (context, block) {
    if (block.block.type == 'thematic_break') {
      return const Divider(thickness: 2);
    }
    return block.defaultWidget;
  },
);
```

Return `null` to use the default widget.

