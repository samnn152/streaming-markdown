# Publishing Checklist (pub.dev)

This file documents the release flow for `animated_streaming_markdown`.

## 1. Preconditions

- Ensure working tree is clean.
- Ensure Git user/email is configured.
- Ensure you are authenticated for pub.dev:

```bash
dart pub login
```

## 2. Versioning

- Update `pubspec.yaml` version.
- Add a matching entry in `CHANGELOG.md`.

## 3. Quality Gates

Run before publish:

```bash
dart format .
dart analyze
flutter test
flutter pub publish --dry-run
```

## 4. Publish

When dry-run has no warnings/errors:

```bash
flutter pub publish
```

## 5. Post Publish

- Tag release in Git.
- Push commit and tag.
- Create release notes from `CHANGELOG.md`.
