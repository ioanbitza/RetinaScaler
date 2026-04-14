# Development Guide

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 6.0 (Swift Package Manager) |
| UI | SwiftUI (`MenuBarExtra` with `.window` style) |
| Display Control | CoreGraphics, IOKit |
| HiDPI Virtual | `CGVirtualDisplay` (private API) |
| HDR | `CoreDisplay` (private API) |
| Night Shift | `CoreBrightness` / `CBBlueLightClient` (private API) |
| DDC/CI | `IOAVService` via IOKit (private API) |
| CI/CD | GitHub Actions |

## Architecture

```
Sources/
  RetinaScalerApp.swift      App entry point, AppDelegate with signal handlers + PID file
  MenuBarView.swift           SwiftUI menu bar panel (per-display cards, settings)
  DisplayManager.swift        Central state manager (@Observable), per-display state
  DisplayDetector.swift       Enumerates displays via CGGetOnlineDisplayList + IOKit EDID
  DisplayModeService.swift    Reads/switches CGDisplayModes
  VirtualDisplayManager.swift CGVirtualDisplay creation, mirror config, mode switching
  OverrideManager.swift       Display override plist generation and installation
  DisplayArrangement.swift    Display positioning presets via CGConfigureDisplayOrigin
  DDCManager.swift            DDC/CI brightness/contrast via IOAVService I2C
  HDRManager.swift            HDR toggle via CoreDisplay private API
  NightShiftManager.swift     Night Shift via CoreBrightness CBBlueLightClient
  HotkeyManager.swift         Global + local keyboard shortcuts via NSEvent monitors
  LaunchAtLogin.swift         SMAppService login item management
  Models.swift                ExternalDisplay, DisplayModeInfo, HiDPIResolution, errors
```

### Key Design Decisions

**Virtual Display Reuse**: The `CGVirtualDisplay` object is created once and kept alive for the app's entire lifetime. Switching between virtual HiDPI resolutions reuses the existing object — no destroy/recreate cycle. This avoids retain/release issues with ObjC private APIs and eliminates display flicker on resolution change.

**Raw Pointer Storage**: The virtual display object is stored as `UnsafeMutableRawPointer` to completely bypass ARC. ObjC runtime `alloc`/`init` via `@convention(c)` function pointers doesn't interact correctly with Swift ARC, causing premature deallocation. macOS automatically destroys the virtual display when the process exits.

**Per-Display State**: `DisplayManager` uses dictionaries keyed by `CGDirectDisplayID` for modes, brightness, contrast, DDC availability, and HDR status. This supports multi-monitor setups where each display has independent state.

**Display Override Plists**: Installed at `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-XXXX`. These declare `scale-resolutions` entries (16-byte big-endian structs: backing width, backing height, flags, reserved) that instruct macOS to expose HiDPI modes.

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run debug
.build/debug/RetinaScaler
```

**Requirements:** Xcode 16+ (Swift 6.0), macOS 14.0+

## Git Flow

This project uses **Git Flow**:

```
main              production releases, tagged with semver
  |
  +── hotfix/*    critical fixes from main → merge to main AND develop
  |
  +── release/*   release prep from develop → merge to main AND develop
  |
develop           active development, integration branch
  |
  +── feature/*   new features from develop → merge back to develop
```

### Branches

| Branch | Purpose | Push access |
|--------|---------|-------------|
| `main` | Stable releases | PR only — nobody pushes directly |
| `develop` | Active development | Owner direct push, contributors via PR |
| `feature/*` | New features | Owner creates from develop |
| `release/*` | Release candidates | Owner creates from develop |
| `hotfix/*` | Production fixes | Owner creates from main |

### Merge Strategy

All merges use `--no-ff` (merge commit) to preserve branch topology, except external contributor PRs which are squash-merged for a clean commit.

### Making a Release

1. Create `release/x.y.z` branch from `develop`
2. Apply final bugfixes on the release branch (no new features)
3. Open PR `release/x.y.z` → `main` (merge commit `--no-ff`)
4. CI must pass before merge
5. After merge, go to **Actions > Release > Run workflow** — select major, minor, or patch
6. Merge the release branch back to `develop` (`--no-ff`)

### Hotfix

1. Create `hotfix/description` from `main`
2. Fix, commit, push
3. PR to `main` (merge commit `--no-ff`)
4. Trigger patch release via Actions
5. Merge `main` back to `develop` (`--no-ff`)

### Branch Protection

| Branch | Direct push | PR required | CI check | Approvals |
|--------|-------------|-------------|----------|-----------|
| `main` | Nobody | Yes | `build` (strict) | 0 (owner self-merges) |
| `develop` | Owner (bypass) | Yes (external contributors) | `build` | 1 (for external PRs) |

### CI/CD Pipelines

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `ci.yml` | Push to develop/release/hotfix, PRs to develop/main | Build debug + release |
| `release.yml` | Manual dispatch on main | Build, sign, package DMG + ZIP + checksums, create GitHub Release |

## Private APIs Used

These are undocumented and may break with macOS updates:

| API | Framework | Purpose |
|-----|-----------|---------|
| `CGVirtualDisplay` | CoreGraphics | Create virtual displays for HiDPI mirroring |
| `CGVirtualDisplayDescriptor` | CoreGraphics | Configure virtual display properties |
| `CGVirtualDisplayMode` | CoreGraphics | Define resolution/refresh rate modes |
| `CGVirtualDisplaySettings` | CoreGraphics | Apply HiDPI flag and modes |
| `CBBlueLightClient` | CoreBrightness | Night Shift control |
| `CGDisplaySetHDRMode` | CoreDisplay | HDR toggle |
| `IOAVServiceCreate` | IOKit | DDC/CI I2C communication |
| `IOAVServiceReadI2C` | IOKit | Read brightness/contrast from monitor |
| `IOAVServiceWriteI2C` | IOKit | Set brightness/contrast on monitor |

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for external contributor guidelines.
