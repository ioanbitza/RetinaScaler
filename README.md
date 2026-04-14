# RetinaScaler

Free, open-source macOS menu bar app that enables HiDPI (Retina) scaling on external monitors where macOS doesn't natively offer it.

Built for ultrawide and high-refresh-rate displays like the Samsung Odyssey G9 Neo (5120x1440 @240Hz), but works with any external monitor.

## What It Does

macOS only offers HiDPI modes on displays where the backing resolution (2x logical) fits within the panel's native resolution. For most external monitors, this means no HiDPI at all — text looks fuzzy compared to the built-in Retina display.

RetinaScaler fixes this by:

1. **Installing display override plists** that tell macOS to offer HiDPI modes on your external monitor
2. **Creating virtual displays** for resolutions that exceed the native panel's HiDPI capability, using mirror mode to render at higher backing resolution

### Two Modes

| Mode | How it works | Refresh Rate | Best for |
|------|-------------|-------------|----------|
| **HiDPI Native** | Uses macOS display overrides to unlock HiDPI modes directly on the physical display | Full (240Hz) | Daily use — sharp text, zero overhead |
| **HiDPI Virtual Display** | Creates a virtual display at higher resolution, mirrors your physical display to it | Full (240Hz target, minor compositor overhead) | Higher resolutions between 1080p-1440p |

### Features

- Per-display resolution picker with HiDPI and standard modes
- Refresh rate switching (240Hz / 120Hz / 60Hz)
- DDC brightness and contrast control (over DisplayPort/HDMI, no extra software needed)
- HDR toggle
- Night Shift toggle (system-wide)
- Display arrangement presets (left/right/above/below)
- Keyboard shortcuts (Ctrl+Opt+H: HiDPI, Ctrl+Opt+R: HDR, Ctrl+Opt+Arrow: Brightness, Ctrl+Opt+F: Cycle Hz)
- Launch at login
- Virtual display management with force cleanup for orphaned displays
- Dark-mode menu bar UI with card-based layout

## Download

Go to [Releases](https://github.com/ioanbitza/RetinaScaler/releases) and download the latest `.dmg` or `.zip`.

### Installation

1. Download `RetinaScaler-x.x.x.dmg`
2. Open the DMG and drag **RetinaScaler** to Applications
3. Launch from Applications — it appears as a menu bar icon
4. On first HiDPI activation, macOS will ask for admin password to install display overrides

### Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac
- External monitor connected via DisplayPort, HDMI, or USB-C

### Note on Gatekeeper

Since the app is ad-hoc signed (not notarized), macOS may block it on first launch. To open:

1. Right-click the app > Open (or System Settings > Privacy & Security > Open Anyway)
2. This is only needed once

## Bug Reports

Found a bug? [Open an issue](https://github.com/ioanbitza/RetinaScaler/issues/new) with:

- **macOS version** (e.g., macOS 15.4)
- **Mac model** (e.g., MacBook Pro M4 Max)
- **Monitor model** and connection type (e.g., Samsung G9 Neo via DisplayPort)
- **What happened** vs **what you expected**
- **Steps to reproduce**
- Screenshots if applicable

## Building from Source

```bash
# Clone
git clone https://github.com/ioanbitza/RetinaScaler.git
cd RetinaScaler

# Build
swift build

# Run
.build/debug/RetinaScaler

# Release build
swift build -c release
```

Requires Xcode 16+ (Swift 6.0) and macOS 14+.

## Development

### Git Flow

This project uses **Git Flow**:

```
main             stable releases, tagged with semver
  |
  +-- hotfix/*   critical fixes (branch from main, merge to main + develop)
  |
develop          active development, integration branch
  |
  +-- feature/*  new features (branch from develop, merge back to develop)
  +-- release/*  release prep (branch from develop, merge to main + develop)
```

### Branches

| Branch | Purpose | Push access |
|--------|---------|-------------|
| `main` | Production releases | PR only (nobody pushes directly) |
| `develop` | Active development | Owner direct, contributors via PR |
| `feature/*` | New features | Owner |
| `release/*` | Release candidates | Owner |
| `hotfix/*` | Critical production fixes | Owner |

### Making a Release

1. Create `release/x.y.z` branch from `develop`
2. Apply release bugfixes on the release branch
3. PR `release/x.y.z` -> `main` (merge commit)
4. After merge, go to **Actions > Release > Run workflow** and select version bump type
5. Merge release branch back to `develop`

### Hotfix

1. Create `hotfix/description` from `main`
2. Fix, commit, push
3. PR to `main` (merge commit)
4. Trigger patch release
5. Merge `main` back to `develop`

### Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for external contributor guidelines.

## Tech Stack

- **Language**: Swift 6.0 (Swift Package Manager)
- **UI**: SwiftUI (MenuBarExtra)
- **APIs**: CoreGraphics, IOKit, CGVirtualDisplay (private), CoreBrightness (private)
- **CI/CD**: GitHub Actions

## License

MIT

## Credits

Made by [Ioan Bitza](https://github.com/ioanbitza) at [ASTRALBYTE](https://github.com/ioanbitza).
