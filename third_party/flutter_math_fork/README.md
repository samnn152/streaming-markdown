# Embedded flutter_math_fork renderer

This directory records the provenance of the view-only math renderer embedded
under `lib/src/third_party/flutter_math`.

- Upstream: `simpleclub/flutter_math`
- Upstream package: `flutter_math_fork` 0.7.4
- Source license: Apache-2.0
- KaTeX font license: MIT

The embedded copy removes the package's independent selectable-math subsystem
because selection is coordinated by `AnimatedStreamingMarkdown`. Its
layout-builder baseline adapter uses Flutter's public `LayoutBuilder` plus a
baseline-forwarding proxy so the same source compiles from Flutter 3.10 through
current stable releases. Font references use the
`animated_streaming_markdown` package namespace.
