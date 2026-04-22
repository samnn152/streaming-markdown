# Streaming Markdown Flutter Example

Flutter demo app for visual markdown parsing with `animated_streaming_markdown`.

## What it shows

- Loads GitHub's GFM spec file: `assets/github_gfm_spec.md`
- Uses `RopeString` + `RopeMarkdownParser` (Dart-only)
- If native library is available: uses `TreeSitterMarkdownParser` and renders node tree
- Lets you append markdown chunks and parse again live

## Run

From repository root:

```bash
cd example
flutter run
```

Run the standalone Markdown cases catalog:

```bash
cd example
flutter run -t lib/markdown_cases_demo.dart
```

## Asset source

`assets/github_gfm_spec.md` is downloaded from:

`https://raw.githubusercontent.com/github/cmark-gfm/master/test/spec.txt`
