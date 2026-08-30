# Streaming Markdown Flutter Example

Flutter chatbot and deterministic feature labs for
`animated_streaming_markdown`.

## What it shows

- A real streaming chatbot for Ollama, OpenAI-compatible APIs, Claude, Gemini,
  and Grok.
- Stable per-message parser and renderer state when later messages are added.
- The offline Selection lab, including flat formatted-text selection,
  source-backed copy strategies, tables, code, and inline code.
- The offline Streaming link & custom widget lab, including incomplete-link
  semantics, tappable temporary destinations, and character-level selection in
  an interactive custom object.
- A standalone Markdown cases catalog backed by the bundled GFM fixture.
- A parser benchmark for pure Dart, synchronous native, and isolate-worker
  paths when the native parser is available.

## Run

From repository root:

```bash
cd example
flutter run
```

Run the standalone Markdown cases catalog:

```bash
cd example
flutter run -t lib/src/demos/markdown_cases_demo.dart
```

Run the parser benchmark:

```bash
cd example
flutter run -t lib/src/demos/parser_benchmark_demo.dart
```

The main app's link and pointer icons open the two offline labs. They do not
need an API key or network response and are the fixtures used by the public
0.3.7 preview recording.

## Asset source

`assets/github_gfm_spec.md` is downloaded from:

`https://raw.githubusercontent.com/github/cmark-gfm/master/test/spec.txt`
