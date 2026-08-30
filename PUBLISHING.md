# Publishing Checklist (pub.dev)

This file documents the release flow for `animated_streaming_markdown`.

## 1. Preconditions

- Ensure working tree is clean.
- Ensure Git user/email is configured as the package maintainer.
- Ensure GitHub CLI and Git operations use the intended GitHub account:

```bash
git var GIT_COMMITTER_IDENT
gh auth status
gh api user --jq .login
```

For the normal release path, pub.dev authentication is provided by the
repository's trusted-publisher/OIDC workflow. A local `dart pub login` session
is not required.

## 2. Versioning

- Update `pubspec.yaml` version.
- Update the matching iOS and macOS podspec versions.
- Add a matching entry in `CHANGELOG.md`.

## 3. Quality Gates

Run before publish:

```bash
find lib test tool example/lib example/test example/integration_test \
  -name '*.dart' -not -path 'lib/src/third_party/*' -print0 |
  xargs -0 dart format
flutter analyze
flutter test
(
  cd example
  flutter build web --base-href /demo/chat/ --output ../website/static/demo/chat
)
(
  cd website
  npm ci
  npm run build
)
flutter pub publish --dry-run
```

The example web build above is also the static chatbot demo embedded in the
documentation site, so rebuild it whenever release notes or docs claim the live
demo matches the shipped example.

The release-tag workflow does not deploy the documentation site. Push the
committed docs and `website/` assets to `dev`, then require the separate
`Deploy Documentation` workflow to pass before tagging.

Refresh the preview recording when the release changes visible behavior. The
recording must use the deterministic offline Selection lab and Streaming link &
custom widget fixtures rather than a network response. Keep the source MP4 at
least 1280 pixels wide and the README GIF at least 960 pixels wide; verify both
dimensions and duration with `ffprobe` before committing them.

Build and verify the Tree-sitter WASM asset before every release. The generated
files are committed and published with the package so app developers do not need
to add scripts, copy assets, or change web configuration:

```bash
tool/build_wasm.sh
tool/verify_wasm_assets.sh
```

`tool/verify_wasm_assets.sh` compares the generated asset manifest against the
current `packages/tree-sitter`, `packages/tree-sitter-markdown`, and `src`
source/header files. If those inputs change, rebuild and commit the WASM assets.
Release CI verifies the committed output but does not regenerate it.

Published versions support Flutter web without consumer-side configuration. Do
not bundle local `.env` files in the example web build; cloud API keys should be
entered at runtime or provided with local `--dart-define` values during
development only.

For `0.3.7`, keep the public documentation aligned with the shipped selection
engine: source-backed directional selection, flat highlighting across text and
non-text content, TextField-like edge scrolling, stable streamed state, and
rich clipboard with plain fallback on Web, Android, iOS, macOS, Windows, and
Linux. Verify that examples use `^0.3.7` and that every public API named in the
docs is exported from `animated_streaming_markdown.dart`.

The compatibility floor is Flutter `>=3.10.0` with Dart `>=3.0.0 <4.0.0`.
Run the package and example checks once on Flutter 3.10.x and once on current
stable. The text-scaling adapter must retain the linear `textScaleFactor` path
on 3.10 and use nonlinear `TextScaler` when the newer SDK exposes it.

The Flutter 3.10 CI job resolves the root package with
`flutter pub get --no-example`. The example Android host uses the modern Gradle
Kotlin DSL template, which Flutter 3.10 cannot identify, while the package's
Android plugin metadata remains compatible with v2-embedding apps from that
SDK. The same legacy job still builds the example for Web after the package
analyze and test gates, so Dart/widget compatibility is not skipped.

On native release runners, smoke-test rich copy on Android, iOS, macOS,
Windows, and Linux by pasting into a rich-text-capable receiver. On Web, test
the browser copy path and confirm both HTML and plain text flavors. If the host
rejects HTML, the operation must still complete with plain text.

For release CI on a platform where the bundled native library should be
available, require the native parser gate:

```bash
REQUIRE_STREAMING_MARKDOWN_NATIVE=true flutter test
```

Run the parser benchmark demo before publishing performance-sensitive changes:

```bash
cd example
flutter run -d macos lib/src/demos/parser_benchmark_demo.dart
```

Record the section count, iteration count, native availability, and median
times in the release notes when parser or renderer performance changes.

## 4. Pre-release platform matrix

Commit and push the release candidate, then run the reusable selection matrix
against that exact branch before creating the release tag:

```bash
git push origin dev
gh workflow run selection-integration.yml --ref dev
gh run list --workflow selection-integration.yml --branch dev --limit 1
```

Do not create the release tag until the Linux, Windows, macOS, Chrome, Android,
and iOS jobs have all passed. The tag workflow repeats this matrix and also
runs Flutter 3.10.7 compatibility, current stable tests, web/WASM builds, and a
publish dry-run.

## 5. Publish

The release workflow expects an unprefixed semantic-version tag:

```bash
git tag -a 0.3.7 -m "Release 0.3.7"
git push origin 0.3.7
```

`.github/workflows/release-publish.yml` creates the GitHub release and
publishes to pub.dev through OIDC only after every required job succeeds. Do
not run `flutter pub publish` locally during the normal release flow, because
that would bypass the repository's compatibility and platform gates.

## 6. Post Publish

- Confirm the tagged workflow is green.
- Confirm the GitHub release points at the intended commit.
- Confirm pub.dev serves the matching version and updated README preview.
- Close fixed issues only after the published package is visible.
