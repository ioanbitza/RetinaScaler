# Contributing to RetinaScaler

Thanks for your interest in contributing!

## Git Flow

This project uses **Git Flow**. Please follow these rules:

### For external contributors

1. **Fork** the repository
2. Create a branch from `develop` in your fork
3. Make your changes (one feature or fix per PR)
4. Ensure `swift build` and `swift build -c release` pass locally
5. Open a **Pull Request to `develop`** (never to `main`)
6. Describe your changes clearly in the PR description

### Branch naming

- `feature/description` — new features
- `fix/description` — bug fixes

### What NOT to do

- Do not open PRs directly to `main`
- Do not include unrelated changes in a PR
- Do not modify CI/CD workflows without discussion first

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run
.build/debug/RetinaScaler
```

## Requirements

- macOS 14.0+
- Swift 6.0+ (Xcode 16+)
- The app uses private macOS APIs (CGVirtualDisplay, CoreBrightness) — it cannot be submitted to the Mac App Store

## Questions?

Open an issue for discussion before starting large changes.
