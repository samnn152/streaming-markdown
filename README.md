<a id="readme-top"></a>

<p align="center">
  <a href="https://samnn.dev/live-chat-demo">
    <img src="https://samnn.dev/img/preview/chat-demo.gif" alt="animated_streaming_markdown 0.3.7 selection, incomplete-link, and custom-widget demo" width="720">
  </a>
</p>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![License][license-shield]][license-url]
[![Pub Version][pub-shield]][pub-url]

<br />
<div align="center">
  <a href="https://github.com/samnn152/streaming-markdown">
    <img src="assets/branding/logo.svg" alt="animated_streaming_markdown logo" width="120" height="120">
  </a>

<h3 align="center">animated_streaming_markdown</h3>

  <p align="center">
    Streaming Markdown parser + renderer for Flutter, optimized for incremental append flows.
    Native targets and Flutter web are supported, including zero-config Tree-sitter WASM assets for published builds.
    <br />
    <a href="https://samnn.dev"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/samnn152/streaming-markdown/tree/main/example">View Demo</a>
    &middot;
    <a href="https://github.com/samnn152/streaming-markdown/issues/new?labels=bug">Report Bug</a>
    &middot;
    <a href="https://github.com/samnn152/streaming-markdown/issues/new?labels=enhancement">Request Feature</a>
  </p>
</div>

## Latest Update

- **0.3.7 source-backed controller**: directional selection now lives in an optional `AnimatedMarkdownSelectionController`, so pointer, keyboard, copy, and programmatic changes share one source of truth.
- **TextField-like selection auto-scroll**: edge dragging advances every frame, keeps the moving endpoint revealed, supports vertical viewports and horizontal tables, and stops without momentum on release.
- **Lazy sliver selection**: `AnimatedStreamingMarkdownSelectionArea` coordinates selection across mounted sliver children without disabling lazy rendering.
- **Browser-like flat highlight**: selection paints as one continuous layer per line, supports touch long-press and handles, and includes non-text content such as images and LaTeX in its real laid-out bounds.
- **Semantic streaming links and selectable custom widgets**: incomplete links expose label, destination, completion state, and source offsets without leaking raw syntax; custom blocks can opt into atomic, text, or fragment-level selection.
- **Stable streaming state**: incremental appends preserve settled render state and source-backed selection; the chat example keeps each assistant renderer alive while messages are recycled by the list.
- **Rich clipboard on every supported target**: Web, Android, iOS, macOS, Windows, and Linux receive HTML plus plain text, with a safe plain-text fallback when the host clipboard rejects rich data.
- **Animation without layout jolts**: settled word tokens compact into lighter static spans while preserving token geometry; the example defaults to the original `Fade` preset and also includes `Gravity`.
- **Flutter web is first-class**: published builds include the generated Tree-sitter WASM parser asset, so app developers do not need to edit `web/index.html` or copy files manually.
- **KaTeX-style LaTeX rendering**: inline `$...$` / `\(...\)` and display `$$...$$` / `\[...\]` math render through the bundled pure-Dart/Flutter renderer derived from `flutter_math_fork`; no separate math dependency is required.
- **Real chatbot example**: the example app can connect to local Ollama plus ChatGPT/OpenAI, Claude, Gemini, and Grok-compatible cloud APIs.

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#documentation">Documentation</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

## About The Project

`animated_streaming_markdown` provides 2 main layers:

- **Parser**: `MarkdownStreamParser` for typed `replace`/`append` requests
- **Renderer**: `AnimatedStreamingMarkdown` for block rendering, token reveal animations, inline images, links, selection, and KaTeX-compatible LaTeX math
- **Tables**: stable shared-width Markdown tables with left-aligned viewport framing and row-by-row reveal during streaming

It is designed for chat-like or streaming text interfaces where markdown arrives progressively and needs stable UI updates.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

* [![Flutter][Flutter-badge]][Flutter-url]
* [![Dart][Dart-badge]][Dart-url]
* [![Tree-sitter][TreeSitter-badge]][TreeSitter-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

### Prerequisites

- Flutter `>=3.10.0`
- Dart SDK `>=3.0.0 <4.0.0`
- Native toolchain for your target platform (Android/iOS/macOS/Linux/Windows)
- No extra setup is required for Flutter web consumers; the package ships the generated WASM parser asset and falls back safely when needed.

The package keeps a Flutter `3.10.0` compatibility path and uses newer
nonlinear text scaling APIs when the running SDK provides them. Current stable
Flutter releases are supported as well.

### Installation

1. Add dependency:
   ```yaml
   dependencies:
    animated_streaming_markdown: ^0.3.7
   ```
2. Install packages:
   ```sh
   flutter pub get
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Usage

### 1) Start parser worker and stream markdown

```dart
final parser = MarkdownStreamParser();
await parser.start();

final setResult = await parser.replace('# Hello');

final appendResult = await parser.append('\n\nStreaming **markdown** chunk...');
```

### 2) Render blocks with `AnimatedStreamingMarkdown`

```dart
AnimatedStreamingMarkdown(
  blocks: appendResult.blocks,
  tokenStaggerDelay: const Duration(milliseconds: 180),
  tokenAnimationDuration: const Duration(milliseconds: 240),
  enableSelection: true,
);
```

The built-in animation is a `Fade` reveal. Supply `tokenAnimationBuilder` only
when opting into a custom effect such as Gravity or Rotate in.

### 3) Control selection and selectable slivers

Box mode creates its selection area internally. Supply a controller only when
the app needs to observe or change the source range:

```dart
final selectionController = AnimatedMarkdownSelectionController();

AnimatedStreamingMarkdown(
  blocks: appendResult.blocks,
  enableSelection: true,
  selectionController: selectionController,
  selectionScrollPadding: const EdgeInsets.all(20),
);

// selectionController.selection = const TextSelection(...);
// selectionController.selectAll();
```

Sliver mode needs one wrapper around the `CustomScrollView`. The wrapper and
renderer must share the controller, and one wrapper manages one Markdown
renderer:

```dart
AnimatedStreamingMarkdownSelectionArea(
  controller: selectionController,
  scrollPadding: const EdgeInsets.all(20),
  child: CustomScrollView(
    slivers: [
      AnimatedStreamingMarkdown(
        blocks: appendResult.blocks,
        asSliver: true,
        enableSelection: true,
        selectionController: selectionController,
      ),
    ],
  ),
);
```

Dispose an app-owned controller with the surrounding `State`.

### 4) Keep a streaming renderer stable

Keep one `MarkdownStreamParser` alive for each active document and call
`append(chunk)` only for new chunks. Preserve the identity of the widget that
owns a message renderer (for example with a stable message key in a
`ListView`); do not create a new parser or changing renderer key from `build`.
This lets settled token animation, selection, and controller state survive
later messages and list recycling. Use `replace(markdown)` when an update is a
complete snapshot rather than an append.

### 5) Render LaTeX math with KaTeX-compatible syntax

LaTeX is supported in both inline and display forms:

```dart
AnimatedStreamingMarkdown.fromMarkdown(
  markdown: r'''
Inline math: $x^2 + y^2 = z^2$

Display math:

$$
\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
$$
''',
);
```

Use `latexBuilder` to wrap or replace the default bundled math widget:

```dart
AnimatedStreamingMarkdown(
  blocks: appendResult.blocks,
  latexBuilder: (context, latex) {
    return latex.defaultWidget;
  },
);
```

Custom image and LaTeX widgets retain the renderer's semantic selection proxy.
When `blockBuilder` replaces a complete block with a non-text object, declare
the object's plain-text meaning with `AnimatedMarkdownSelectable`:

```dart
blockBuilder: (context, block) {
  return AnimatedMarkdownSelectable(
    plainText: block.block.content,
    child: MyCustomMarkdownObject(block: block.block),
  );
},
```

The default constructor selects the custom object atomically. For a custom text
renderer, including Flutter's `SelectableText`, use the character-level
constructor:

```dart
return AnimatedMarkdownSelectable.text(
  plainText: block.block.content,
  child: SelectableText(block.block.content),
);
```

For a composite object, use `AnimatedMarkdownSelectable.fragments` and wrap
each visible text region with `AnimatedMarkdownSelectionFragment`, supplying
its local `plainTextStart`. Buttons and other siblings remain interactive while
the declared fragments join the surrounding Markdown selection. Plain/raw/rich
copy always comes from the controller's original Markdown source.

Incomplete streaming links are also exposed semantically through
`MarkdownBlock.inlineLinks`. By default, `[Hel` paints nothing,
`[Hello](https://hello` paints a tappable `https://hello`, and the completed
`[Hello](https://hello)` paints the linked label. Override only the temporary
projection with `incompleteLinkTextBuilder` when an application prefers the
label or wants to suppress the construct until completion.
Only a direct inline link at the active streamed tail is provisional; code,
autolinks, images, and escaped opening brackets are not reclassified.

### 6) Important APIs

- `MarkdownStreamParser.start()`
- `MarkdownStreamParser.replace(markdown)`
- `MarkdownStreamParser.append(chunk)`
- `MarkdownStreamParser.parse(operation, text)`
- `MarkdownStreamParser.dispose()`
- `MarkdownSyncParser.parseMarkdown(markdown)`
- `warmUpStreamingMarkdownParser(includeWorker: true)`
- `AnimatedStreamingMarkdown(...)`
- `AnimatedStreamingMarkdown.fromMarkdown(...)`
- `AnimatedStreamingMarkdownSelectionArea(...)`
- `AnimatedMarkdownSelectionController`
- `AnimatedMarkdownSelectionValue`
  - `sourceText`
  - `selection`
  - `hasSelection`
  - `selectedMarkdown`
- Renderer options: `blocks`, `asSliver`, `enableSelection`,
  `selectionStrategy`, `selectionController`, `selectionScrollPadding`,
  `tokenStaggerDelay`, `tokenAnimationDuration`, `tokenAnimationBuilder`,
  `tokenCompaction`, `showCodeBlockCopyButton`, `blockBuilder`, `imageBuilder`,
  `latexBuilder`, `incompleteLinkTextBuilder`, `AnimatedMarkdownSelectable`

`selectionStrategy` accepts `plain`, `raw`, or `rich`. Rich copy keeps the
selected source range as the authority and supplies HTML and plain text to the
clipboard. See [Selection Copy](https://samnn.dev/selection-copy) for the
platform details and fallback behavior.

For a complete integration sample, check [`example/lib/src/demos/markdown_cases_demo.dart`](example/lib/src/demos/markdown_cases_demo.dart).
For the full chatbot sample with Ollama, ChatGPT/OpenAI, Claude, Gemini, and Grok providers, check [`example/lib/main.dart`](example/lib/main.dart).

## Documentation

- [Documentation site](https://samnn.dev)
- [Live web demo and 0.3.7 interaction recording](https://samnn.dev/live-chat-demo)
- [Package page](https://pub.dev/packages/animated_streaming_markdown)
- [Generated API reference](https://pub.dev/documentation/animated_streaming_markdown/latest/)
- [Example app](https://github.com/samnn152/streaming-markdown/tree/main/example)
- [Migration guide: 0.2.x to 0.3.x](docs/migration-0-3.mdx)

The documentation site is built with Docusaurus from [`docs/`](docs) and
deployed to GitHub Pages by [`Deploy Documentation`](.github/workflows/docs-pages.yml).

Run the docs site locally:

```sh
cd website
npm ci
npm run start
```

Build the static site:

```sh
cd website
npm run build
```

### Migration notes for 0.3.0

`0.3.0` keeps the `0.2.x` API available, but the preferred names now describe
the package behavior more directly:

| 0.2.x name | 0.3.x preferred name |
| --- | --- |
| `StreamingMarkdownParseWorker` | `MarkdownStreamParser` |
| `request(op: 'set', ...)` | `replace(markdown)` |
| `request(op: 'append', ...)` | `append(chunk)` |
| `StreamingMarkdownParseResult.renderNodes` | `MarkdownParseResult.blocks` |
| `StreamingMarkdownRenderView` | `AnimatedStreamingMarkdown` |
| `nodes` | `blocks` |
| `sliver` | `asSliver` |
| `tokenArrivalDelay` | `tokenStaggerDelay` |
| `tokenFadeInDuration` | `tokenAnimationDuration` |
| `tokenFadeInRelativeToDelay` | `tokenAnimationDurationFactor` |
| `allowUnclosedInlineDelimiters` | `allowIncompleteInlineSyntax` |
| `enableTextSelection` | `enableSelection` |
| `customBlockBuilder` | `blockBuilder` |
| `markdownTheme` | `theme` |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Roadmap

- Done: Incremental parser worker (`replace` / `append`)
- Done: Streaming renderer for markdown block nodes
- Done: Per-token custom animation builder API
- Done: Example with multiple animation presets
- Done: Docusaurus documentation site for `samnn.dev`
- Done: Convenience constructors and sync parser helpers
- Done: Opt-in code block copy button
- Done: KaTeX-compatible LaTeX math rendering
- Done: Render-backed selection with stable ranges, table traversal, and edge auto-scroll
- Next: Performance optimization across parser, rendering, token compaction, and benchmarks
- Next: Feature development guided by real application requirements and user requests

See the [open issues][issues-url] for proposed features and known issues.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Contributions are welcome.

1. Fork the project
2. Create your branch (`git checkout -b feature/your-feature`)
3. Commit your changes (`git commit -m "Add your feature"`)
4. Push branch (`git push origin feature/your-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, repository layout, and
quality gates.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Support

If this package helps you, consider buying me a coffee:

<a href="https://www.buymeacoffee.com/samnn152" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" style="height: 60px !important;width: 217px !important;" ></a>

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## License

Distributed under the Apache-2.0 License. See [`LICENSE`](LICENSE) for details.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contact

- Documentation: [https://samnn.dev](https://samnn.dev)
- API reference: [https://pub.dev/documentation/animated_streaming_markdown/latest/](https://pub.dev/documentation/animated_streaming_markdown/latest/)
- Repository: [https://github.com/samnn152/streaming-markdown](https://github.com/samnn152/streaming-markdown)
- Issues: [https://github.com/samnn152/streaming-markdown/issues](https://github.com/samnn152/streaming-markdown/issues)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Acknowledgments

* [Tree-sitter](https://tree-sitter.github.io/tree-sitter/)
* [tree-sitter-markdown](https://github.com/tree-sitter-grammars/tree-sitter-markdown)
* [Flutter](https://flutter.dev/)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/samnn152/streaming-markdown.svg?style=for-the-badge
[contributors-url]: https://github.com/samnn152/streaming-markdown/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/samnn152/streaming-markdown.svg?style=for-the-badge
[forks-url]: https://github.com/samnn152/streaming-markdown/network/members
[stars-shield]: https://img.shields.io/github/stars/samnn152/streaming-markdown?style=for-the-badge&logo=github&label=Stars
[stars-url]: https://github.com/samnn152/streaming-markdown/stargazers
[issues-shield]: https://img.shields.io/github/issues/samnn152/streaming-markdown.svg?style=for-the-badge
[issues-url]: https://github.com/samnn152/streaming-markdown/issues
[license-shield]: https://img.shields.io/github/license/samnn152/streaming-markdown.svg?style=for-the-badge
[license-url]: https://github.com/samnn152/streaming-markdown/blob/main/LICENSE
[pub-shield]: https://img.shields.io/pub/v/animated_streaming_markdown?style=for-the-badge
[pub-url]: https://pub.dev/packages/animated_streaming_markdown
[Flutter-badge]: https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white
[Flutter-url]: https://flutter.dev/
[Dart-badge]: https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white
[Dart-url]: https://dart.dev/
[TreeSitter-badge]: https://img.shields.io/badge/Tree--sitter-2F2F2F?style=for-the-badge
[TreeSitter-url]: https://tree-sitter.github.io/tree-sitter/
