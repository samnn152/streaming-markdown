---
title: "ChatGPT Markdown Blocks Demo"
author: "streaming_markdown example"
tags: [chatgpt, markdown, parser, ui]
---

# ChatGPT Markdown Showcase

This demo includes common blocks that ChatGPT typically emits in long responses: **bold**, *italic*, ***bold italic***, ~~strikethrough~~, `inline code`, and [inline links](https://openai.com).

> [!NOTE]
> This is a callout-style quote block.
> It can contain multiple lines and nested markdown.
>
> - Quoted bullet A
> - Quoted bullet B

## Unordered And Task Lists

- Basic bullet item
- Another bullet with `inline code`
  - Nested bullet level 2
  - Nested bullet level 2 again
- Task list examples:
  - [x] Shipping parser isolate
  - [ ] Add inline span rendering

## Ordered Lists

1. First ordered item
2. Second ordered item
3. Third ordered item
   1. Nested ordered item
   2. Nested ordered item

### Horizontal Rule

---

### Table

| Block Type | Supported In This Demo | Notes |
| --- | --- | --- |
| Heading | Yes | H1-H6 |
| Paragraph | Yes | Plain text block rendering |
| List | Yes | Ordered, unordered, task-like text |
| Quote | Yes | Styled quote container |
| Code Fence | Yes | Monospace dark block |
| Table | Partial | Rendered as monospace grid text |

### Dart Code Block

```dart
void main() {
  final features = <String>['heading', 'list', 'quote', 'code'];
  for (final feature in features) {
    print('Rendered: $feature');
  }
}
```

### Bash Code Block

```bash
flutter pub get
flutter run -d ios
```

### JSON Code Block

```json
{
  "renderer": "node-driven",
  "mode": "incremental",
  "updatedAt": "2026-03-11"
}
```

### Link Reference Style

Use [OpenAI][openai-link] and [Flutter docs][flutter-docs] for details.

[openai-link]: https://openai.com
[flutter-docs]: https://docs.flutter.dev

### Image

![](https://picsum.photos/seed/streaming-markdown-renderer/640/180)

### HTML Block

<details>
  <summary>Click to expand raw HTML</summary>
  <p>This block is useful when ChatGPT emits embedded HTML snippets.</p>
</details>

#### Heading Level 4

Small section title for detailed notes.

##### Heading Level 5

Very small heading level often used for appendix-style notes.

###### Heading Level 6

The smallest heading style in standard markdown.

### Footnote

This sentence includes a footnote reference.[^demo-footnote]

[^demo-footnote]: Footnote text often appears in technical or academic markdown.
