# Streaming Markdown Flutter Example

Flutter demo app for visual markdown parsing with `streaming_markdown`.

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

## Asset source

`assets/github_gfm_spec.md` is downloaded from:

`https://raw.githubusercontent.com/github/cmark-gfm/master/test/spec.txt`
