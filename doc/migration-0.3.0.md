# Migration Guide: 0.2.x to 0.3.0

`0.3.0` renames the primary API to better match what the package does today.
The old `0.2.x` names still work, so migration can be incremental.

## Rename Parser Type

Before:

```dart
final worker = StreamingMarkdownParseWorker();
```

After:

```dart
final parser = MarkdownStreamParser();
```

## Replace String Operations

Before:

```dart
final result = await worker.request(
  op: 'set',
  text: markdown,
  includeNodes: true,
);
```

After:

```dart
final result = await parser.replace(markdown);
```

Before:

```dart
final result = await worker.request(
  op: 'append',
  text: chunk,
  includeNodes: true,
);
```

After:

```dart
final result = await parser.append(chunk);
```

For dynamic operations:

```dart
final result = await parser.parse(
  operation: MarkdownParseOperation.append,
  text: chunk,
);
```

## Rename Render Output

Before:

```dart
final nodes = result.renderNodes;
```

After:

```dart
final blocks = result.blocks;
```

`renderNodes` remains available for existing code.

## Rename Renderer Widget

Before:

```dart
StreamingMarkdownRenderView(
  nodes: result.renderNodes,
);
```

After:

```dart
AnimatedStreamingMarkdown(
  blocks: result.blocks,
);
```

## Rename Renderer Parameters

| 0.2.x | 0.3.0 |
| --- | --- |
| `nodes` | `blocks` |
| `emptyPlaceholder` | `placeholder` |
| `sliver` | `asSliver` |
| `allowUnclosedInlineDelimiters` | `allowIncompleteInlineSyntax` |
| `tokenArrivalDelay` | `tokenStaggerDelay` |
| `onTokenArrivalWait` | `onTokenDelay` |
| `onTokenFadeInEnd` | `onTokenAnimationEnd` |
| `tokenFadeInDuration` | `tokenAnimationDuration` |
| `tokenFadeInRelativeToDelay` | `tokenAnimationDurationFactor` |
| `tokenFadeInCurve` | `tokenAnimationCurve` |
| `debugTokenHighlight` | `showTokenDebugColors` |
| `enableTextSelection` | `enableSelection` |
| `markdownTheme` | `theme` |
| `customBlockBuilder` | `blockBuilder` |

## Rename Supporting Types

| 0.2.x | 0.3.0 |
| --- | --- |
| `MarkdownRenderNode` | `MarkdownBlock` |
| `StreamingMarkdownParseResult` | `MarkdownParseResult` |
| `StreamingMarkdownAnimatedToken` | `AnimatedMarkdownToken` |
| `StreamingMarkdownThemeData` | `AnimatedMarkdownThemeData` |
| `StreamingMarkdownBlockBuilder` | `AnimatedMarkdownBlockBuilder` |
| `StreamingMarkdownBlockBuildContext` | `AnimatedMarkdownBlockContext` |

## Compatibility

The old names remain available in `0.3.0`. Prefer the new names for new code,
examples, docs, and issue discussions.

