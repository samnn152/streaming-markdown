## 0.2.1

- Fix example preview stability when macOS window resizing changes layout.
- Fix example selection toggle to avoid rebuild side effects during active token animations.

## 0.2.0

- Add absolute-timeline token reveal scheduling so animation progress stays correct even when tokens build late/offscreen.
- Add customizable per-token animation API via `tokenAnimationBuilder(BuildContext, StreamingMarkdownAnimatedToken)`.
- Add demo selector with 10 token animation presets.
- Rewrite README in template format and refresh parser/renderer-focused usage documentation.

## 0.1.6

- Add a standalone Markdown cases catalog example with streaming playback.
- Fix tappable links when text selection is enabled.
- Fix tappable inline links in rendered HTML blocks.
- Improve HTML table sizing and spacing.
- Render footnote references and definitions with numbered markers.
- Align task-list checkbox markers with item text.
- Replace Vietnamese-facing strings with English copy.

## 0.1.5

- Fix dangling library-level DartDoc attachment in package entrypoint.
- Add DartDoc coverage for public markdown node models to recover pub points.

## 0.1.4

- Lower package SDK and Flutter lower-bound requirements.
- Relax dependency lower bounds (`ffi`, `html`, `flutter_lints`) to support older toolchains where possible.
- Replace `webview_flutter` HTML block rendering with pure Flutter/DOM rendering for broader platform support.
- Make HTML block height wrap content instead of using a fixed viewport.
- Add web-safe conditional exports and non-FFI stubs so importing the package no longer fails on web targets.
- Clarify package metadata and README that web is not an officially supported platform.

## 0.1.3

- Hotfix iOS/macOS native build by restoring `tree_sitter/parser.h` in vendored tree-sitter include path.
- Regenerate example iOS Pod lockfile to use `animated_streaming_markdown` plugin name.

## 0.1.2

- Rename package to `animated_streaming_markdown`.
- Update plugin platform wiring and example imports for the new package name.

## 0.1.1

- Vendor only required tree-sitter runtime and tree-sitter-markdown parser sources.
- Remove nested git metadata from bundled `packages/tree-sitter*` directories.
- Replace gitlink package entries with tracked vendored source files.

## 0.1.0

- Prepare package metadata for pub.dev publishing.
- Add public DartDoc coverage for exported APIs.
- Improve README with usage and licensing notes.
- Add third-party license document for bundled dependencies.
- Stabilize example token timing defaults for streaming demo.
