# Contributing

Thanks for helping improve `animated_streaming_markdown`.

## Local Setup

```sh
git clone https://github.com/samnn152/streaming-markdown.git
cd streaming-markdown
flutter pub get
```

For the example app:

```sh
cd example
flutter pub get
```

## Repository Layout

- `lib/animated_streaming_markdown.dart`: public package entrypoint.
- `lib/src/parser`: parser adapters.
- `lib/src/worker`: isolate parser worker API.
- `lib/src/model`: block, render, rope, and syntax tree models.
- `lib/src/render`: Flutter rendering, animation, selection, text, and HTML.
- `lib/src/native`: native bindings and platform stubs.
- `example`: demo app and demo content.
- `test`: regression tests and goldens.
- `docs`: Docs.page documentation site.
- `doc`: package reference markdown linked from the README.

## Quality Gates

Run before opening a pull request:

```sh
dart format .
dart analyze
flutter test
```

Run before publishing:

```sh
flutter pub publish --dry-run
```

## Pull Requests

Keep pull requests focused. Parser changes, renderer behavior, selection copy,
native bindings, and documentation are easier to review when they are separated.

Behavior changes should include tests. Visual renderer changes should update
goldens when output intentionally changes.
