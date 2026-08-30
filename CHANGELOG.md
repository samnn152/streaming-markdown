## 0.3.7

- Represent direct inline links as `MarkdownInlineLink` semantic snapshots,
  including the current label, destination, completion state, source, and
  offsets when a stream ends before `)`.
- Stop exposing unfinished link Markdown as literal text. The default renderer
  hides a label-only tail, shows the arriving destination, and switches to the
  linked label on completion. An arriving destination is styled and tappable
  before `)` arrives; `incompleteLinkTextBuilder` allows downstream applications
  to choose label-only or hidden projections without reparsing.
- Keep custom image and LaTeX widgets selectable, and add
  `AnimatedMarkdownSelectable` for fully custom block objects while copy
  remains backed by the original Markdown source. Its default behavior is
  atomic; `.text` adapts `Text`, `RichText`, and Flutter `SelectableText` to
  character-level selection, while `.fragments` and
  `AnimatedMarkdownSelectionFragment` map composite widget regions.
- Keep the first pointer edge collapsed instead of briefly selecting to the
  end of its visual line, and preserve a finalized range when a mobile
  long-press targets a word already inside that selection. A single desktop
  click now dismisses the finalized range without extending a stale anchor,
  while double- and triple-click retain native word and paragraph selection.
- Preserve finalized browser selection across scrolling, tab changes, and
  window changes while still dismissing it for a deliberate primary click
  elsewhere inside the application.
- Add `AnimatedMarkdownSelectionValue` and the optional
  `AnimatedMarkdownSelectionController` for directional, source-backed
  selection, including `clear()` and `selectAll()`.
- Add `AnimatedStreamingMarkdownSelectionArea` for selectable sliver content;
  box renderers continue to host their own selection area automatically.
- Match `TextField` edge-drag behavior with frame-driven vertical and
  horizontal auto-scroll, source-stable anchors, endpoint re-hit-testing, and
  immediate cancellation without fling or post-release momentum.
- Reveal keyboard and programmatic selection endpoints with configurable
  `selectionScrollPadding`, using the same 100 ms caret-reveal timing as
  editable text.
- Preserve directional selections through streaming append, block replacement,
  transient sliver unmounts, and geometry leases while an actively selected
  block changes.
- Keep highlight paint independent from Flutter's transient selection geometry
  clears and batch selectable rehydration, preventing blank or doubled frames
  during mouse, touch, and handle drags on old and current Flutter SDKs.
- Paint selection as one continuous line layer instead of per-token shadows,
  derive animated-word highlights from their actual rendered glyph boxes so
  wrapped lines do not expose token seams or select trailing empty width, cover
  the full decorated inline-code box when its token is completely selected,
  hit-test inline code against its real padded render geometry, flatten its
  selected background into the surrounding line instead of a rounded pill,
  cover the real bounds of inline/block images and LaTeX widgets, and preserve
  touch long-press, handle, and keyboard selection across text and non-text
  content.
- Complete semantic projection and selection geometry for formatted headings,
  callouts, front matter, footnotes, nested HTML blocks, lists, tables, code,
  images, and formulas in both box and lazy sliver renderers.
- Unify plain, raw Markdown, rich HTML, keyboard, context-menu, browser, and
  mobile-toolbar copy paths around the controller source range. Rich clipboard
  writers are included for Web, Android, iOS, macOS, Windows, and Linux, with
  plain-text fallback when a host rejects HTML.
- Keep streamed assistant renderers and their parser/token state alive through
  example chat-list recycling, so adding a message does not replay completed
  responses or reset their selection.
- Add TextField-reference, controller, box/sliver, browser, and offline native
  integration regression coverage for selection and auto-scroll lifecycle.
- Refresh the public demo recording at 1440x900 and the README GIF at 960x600
  with deterministic selection, incomplete-link, and custom-widget fixtures.
- Preserve the Flutter 3.10 minimum while supporting current stable releases by
  embedding the view-only KaTeX renderer and replacing its version-sensitive
  layout callback with a stable `LayoutBuilder` baseline adapter.
- Make the example project's Dart and dependency constraints resolvable from
  Dart 3.0 through current stable, and gate both Flutter 3.10.7 and stable in CI.

## 0.3.6

- Replace overlay-derived selection tracking with render-backed absolute range
  selection, keeping anchors stable through streaming and viewport scrolling.
- Support partial text selection inside tables, selection continuation across
  table boundaries, and vertical/horizontal edge auto-scroll while dragging.
- Compact settled animated tokens into lighter static spans without shifting
  rendered layout, preserving the established word-by-word animation behavior.
- Add the `Gravity` example animation while restoring `Fade` as the default
  example preset.
- Refresh the README/demo video, package API documentation, website
  documentation, and forward roadmap for performance and requested features.
- Remove stale preview and internal validation artifacts from published package
  contents.
- Repository maintenance: normalized historical Git author and committer
  metadata to `samnn152 <ngocsam.ngo@gmail.com>`. Earlier commits may have
  appeared under other local Git identities for the same maintainer, including
  `Ngô Ngọc Sâm`, `Sam Ngo Ngoc`, and machine-local `hider152` emails.

## 0.3.5

- Hotfix pub.dev platform metadata to declare Flutter web support explicitly.
- Keep the published web support messaging aligned with the shipped
  zero-config WASM-backed web implementation.

## 0.3.4

- Add an opt-in code block copy button via `showCodeBlockCopyButton`.
- Add a native parser release gate that can be required in CI with
  `REQUIRE_STREAMING_MARKDOWN_NATIVE=true`.
- Add an Emscripten build script, source-digest asset verification, and web
  loader for zero-config experimental Tree-sitter WASM parsing.
- Add CI/release gates for committed WASM parser assets.
- Allow web parse workers to use Tree-sitter WASM when the generated asset is
  available, with pure-Dart fallback otherwise.
- Promote Flutter web support as zero-config for package consumers by bundling
  generated WASM parser assets as package assets.
- Replace the example app with a real streaming Markdown chatbot for Ollama,
  ChatGPT/OpenAI, Claude, Gemini, and Grok/xAI providers.
- Add a static Flutter web chatbot demo for the documentation site.
- Add inline image rendering customization, intrinsic-size handling, and
  baseline alignment controls.
- Add KaTeX-compatible LaTeX math rendering for inline `$...$` / `\(...\)` and
  display `$$...$$` / `\[...\]` expressions using `flutter_math_fork`.
- Improve chat example render sequencing so streamed Markdown waits for parser,
  block reveal, and token animation settlement before allowing the next send.
- Rework Markdown table rendering to support left-aligned viewport framing,
  row-by-row reveal, more readable colors, and stable shared column widths on
  web and native targets.
- Raise the Dart SDK lower bound to `>=3.0.0` to match the math renderer
  dependency and current Flutter web support.
- Fix selection-on rendering so active selection uses text metrics that match
  the rendered Markdown while idle selection keeps the same token effects as
  selection-off.
- Clean up iOS and macOS podspec release metadata.
- Expand publishing guidance for native verification and parser benchmarks.

## 0.3.3

- Add `AnimatedStreamingMarkdown.fromMarkdown` for complete Markdown snapshots.
- Add `MarkdownSyncParser` with `auto`, `native`, and `dart` backend selection.
- Add `warmUpStreamingMarkdownParser` for shared sync and worker parser warm-up.
- Add a parser benchmark demo comparing pure Dart, sync native, and isolate worker rendering.
- Improve pure-Dart GFM block parsing for headings, quotes, tables, lists, code blocks, footnotes, and link references.
- Add GFM parser content golden tests for `raw` and `content` output.
- Point package documentation metadata and docs links at `https://samnn.dev`.
- Remove the old Docs.page configuration now that Docusaurus is the documentation site.

## 0.3.2

- Add a Docs.page documentation site configuration and MDX documentation pages.
- Add a Docusaurus documentation site for self-hosted `samnn.dev` deployment.
- Point package homepage and documentation metadata at the official pub.dev pages.
- Expand README links around installation, docs, migration, and contribution entry points.
- Add a contributor guide for local setup, repository layout, quality gates, and release flow.
- Add an animated Gemini streaming demo preview for the README.

## 0.3.1

- Reorganize parser, renderer, model, native, and worker internals into clearer layers for contributors.
- Split large renderer modules into smaller focused files while keeping the public package API compatible.
- Move the rope string model under `model/` and clarify parser file names.
- Fix the GitHub stars badge URL used by the README.

## 0.3.0

- Add clearer primary API names: `MarkdownStreamParser`, `AnimatedStreamingMarkdown`, `MarkdownBlock`, Flutter-style token animation timing, and typed parse operations.
- Keep `0.2.x` parser and renderer names available for migration compatibility.
- Refresh README usage and migration notes around the new API names.
- Add package branding asset at `assets/branding/logo.svg`.
- Add renderer-level token animation pause support.
- Improve public Dartdoc coverage for parser results, render blocks, theme data, and renderer configuration.

## 0.2.2

- Fix select-all Markdown copy so complex blocks keep source delimiters and blocks after footnotes are included.
- Improve selection-copy coverage for lists, block quotes, code blocks, tables, HTML blocks, and footnotes.
- Add strict selection regression tests and golden coverage for supported block rendering states.

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
