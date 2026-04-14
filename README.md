<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black?style=flat-square&logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/github/license/ioanbitza/RetinaScaler?style=flat-square" alt="License">
  <img src="https://img.shields.io/github/v/release/ioanbitza/RetinaScaler?style=flat-square" alt="Release">
</p>

# RetinaScaler

**Free, open-source macOS menu bar utility that brings Retina-quality rendering to external monitors.**

Most external monitors have a pixel density below 210 PPI — the threshold Apple uses for "Retina" displays. macOS refuses to offer HiDPI scaling on these panels, leaving text and UI elements looking noticeably softer compared to the built-in display. RetinaScaler solves this by unlocking HiDPI modes that macOS won't enable on its own.

Works with any external monitor — ultrawides, 4K, 1440p, 1080p, any refresh rate.

<p align="center">
  <a href="https://github.com/ioanbitza/RetinaScaler/releases/latest/download/RetinaScaler-1.0.0.dmg"><strong>Download RetinaScaler.dmg</strong></a> · <a href="https://github.com/ioanbitza/RetinaScaler/releases/latest/download/RetinaScaler-1.0.0.zip">ZIP</a> · <a href="https://github.com/ioanbitza/RetinaScaler/releases">All Releases</a>
</p>

---

## Why You Need This

| | Without RetinaScaler | With RetinaScaler |
|---|---|---|
| **Text rendering** | Fuzzy on external displays, sharp only on built-in | Retina-quality text on all displays |
| **UI elements** | Pixel-visible edges, aliased fonts | Smooth, crisp rendering at 2x backing |
| **Available modes** | Only standard resolutions | Full range of HiDPI scaled modes |
| **Display controls** | Scattered across System Settings | Unified menu bar panel for all monitors |

---

## How It Works

macOS renders HiDPI by using a **backing resolution** that is 2x the logical resolution. For example, a 1920x1080 HiDPI mode actually renders at 3840x2160, then downscales to the physical panel. This makes everything look sharp, like on a MacBook Retina display.

The problem: macOS only offers HiDPI if the backing resolution (2x) fits within what it thinks the display can handle. For most external monitors, it doesn't — so you get no HiDPI modes at all.

RetinaScaler provides two mechanisms to fix this:

### HiDPI Native

Installs a **display override plist** that tells macOS your monitor supports HiDPI modes. macOS then exposes these modes directly on the physical display.

- Runs at your monitor's **full refresh rate** (120Hz, 144Hz, 240Hz, etc.)
- **Zero overhead** — macOS handles everything natively
- Best for daily use
- Requires admin password once to install the override file

### HiDPI Virtual Display

For scaled resolutions where the 2x backing exceeds what the physical panel can provide natively, RetinaScaler creates a **virtual display** using macOS private APIs. Your physical monitor mirrors this virtual display, and macOS renders the HiDPI content at the higher backing resolution.

- Enables **any HiDPI resolution** regardless of panel limitations
- Virtual display is created once and **reused** across resolution switches (no flicker)
- Minor compositor overhead due to mirror rendering
- Best for situations where Native modes don't cover the resolution you want

---

## The Menu

RetinaScaler lives in your menu bar. Click the icon to open the control panel. Each connected display gets its own card with independent controls.

### Per-Display Controls

**Display Header**
> Shows the display name, current resolution, refresh rate, and a HiDPI badge when active. Built-in displays show a laptop icon, externals show a monitor icon. Click to expand/collapse.

**HiDPI Native** `@240Hz`
> Lists all native HiDPI modes available on the physical display (unlocked via the override plist). These run at your monitor's full refresh rate with zero overhead. Select any mode to switch instantly.

**HiDPI Virtual Display**
> Lists additional scaled HiDPI resolutions only achievable through virtual display mirroring. These are computed from your monitor's native resolution and aspect ratio, covering a range of logical heights. Select one to activate the virtual display and mirror.

**Disable Virtual HiDPI**
> Appears when a virtual display is active. Reverts to your normal display configuration without mirroring.

**Resolutions**
> Standard (non-HiDPI) display modes sorted by resolution. Useful for quickly switching to a specific resolution without HiDPI.

**Refresh Rate**
> Quick-switch buttons for all refresh rates your monitor supports at its native resolution (e.g., 240Hz, 120Hz, 60Hz). The active rate is highlighted.

**HDR Mode**
> Toggle HDR on/off for displays that support it. Uses macOS CoreDisplay private API.

**Night Shift** *(all displays)*
> Toggle Apple's blue light reduction. This is a system-wide setting — it affects all connected displays simultaneously. Shown once in the menu, not per-display.

**Brightness & Contrast**
> Hardware-level DDC/CI control sliders. Adjusts your monitor's actual backlight and contrast via I2C commands over DisplayPort/HDMI — the same as using the monitor's physical buttons, but from your Mac. Available on monitors that support DDC (most modern displays over DisplayPort or HDMI).

**Arrangement**
> Quick presets to position the display relative to your primary display: Left, Right, Above, Below, or Centered Above.

### Global Settings

**Launch at Login**
> Start RetinaScaler automatically when you log in.

**Keyboard Shortcuts**
> Toggle global keyboard shortcuts on/off. When enabled:

| Shortcut | Action |
|----------|--------|
| `Ctrl + Opt + H` | Toggle HiDPI on/off |
| `Ctrl + Opt + R` | Toggle HDR |
| `Ctrl + Opt + ↑` | Brightness up (+10%) |
| `Ctrl + Opt + ↓` | Brightness down (-10%) |
| `Ctrl + Opt + F` | Cycle through refresh rates |

**Virtual Displays**
> Shows any active virtual displays created by RetinaScaler with their resolution and display ID. The **Remove All Virtual Displays** button forces cleanup — useful if a virtual display got stuck after a crash.

**Refresh Displays**
> Re-detects all connected monitors and refreshes mode lists, DDC status, and HDR state.

---

## Installation

1. Download `RetinaScaler-x.x.x.dmg` from Releases
2. Open the DMG and drag **RetinaScaler** to your Applications folder
3. Launch from Applications — a display icon appears in the menu bar
4. On first HiDPI activation, macOS will prompt for your admin password to install display overrides

### System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac
- External monitor connected via DisplayPort, HDMI, or USB-C/Thunderbolt

### Gatekeeper Notice

The app is ad-hoc signed (not Apple-notarized). macOS will block the first launch:

1. **Right-click** the app > **Open**, or
2. Go to **System Settings > Privacy & Security > Open Anyway**

This is only required once.

### Accessibility Permission

If you enable keyboard shortcuts, macOS will ask for **Accessibility** permission. This is required for global hotkeys to work outside the app. RetinaScaler does not log or transmit any keyboard input.

---

## Compatibility

### What works on external monitors

| Feature | Requires |
|---------|----------|
| HiDPI Native modes | Admin password (once, for override plist) |
| HiDPI Virtual Display | Nothing extra |
| Resolution switching | Nothing extra |
| Refresh rate switching | Nothing extra |
| HDR toggle | Monitor must support HDR |
| Brightness/Contrast (DDC) | Monitor must support DDC/CI over DP/HDMI |
| Arrangement presets | Nothing extra |

### What works on built-in displays

Resolution switching, refresh rate, Night Shift. HiDPI controls are not shown (built-in Retina displays already have HiDPI).

### Known Limitations

- **DDC brightness** may not work on some monitors (USB-C hubs can block DDC signals)
- **Virtual Display HiDPI** at very high resolutions may have minor frame pacing artifacts due to compositor mirror overhead — this is a macOS limitation
- **Night Shift** is system-wide (macOS limitation), cannot be set per-display
- The app uses **private macOS APIs** (`CGVirtualDisplay`, `CoreBrightness`, `CoreDisplay`) — these may change in future macOS updates

---

## Bug Reports

Found a bug? [**Open an issue**](https://github.com/ioanbitza/RetinaScaler/issues/new) with:

- **macOS version** (e.g., macOS 15.4)
- **Mac model** (e.g., MacBook Pro M4 Max, Mac Mini M2)
- **Monitor model** and connection type (e.g., Dell U2723QE via USB-C)
- **What happened** vs **what you expected**
- **Steps to reproduce**
- Screenshots or screen recordings if applicable

---

## Building from Source

```bash
git clone https://github.com/ioanbitza/RetinaScaler.git
cd RetinaScaler

# Debug build
swift build

# Release build
swift build -c release

# Run
.build/debug/RetinaScaler
```

**Requirements:** Xcode 16+ (Swift 6.0), macOS 14.0+

---

## Development & Contributing

- **[DEVELOPMENT.md](DEVELOPMENT.md)** — Architecture, tech stack, Git Flow, CI/CD, private APIs reference
- **[CONTRIBUTING.md](.github/CONTRIBUTING.md)** — Guidelines for external contributors

---

## License

[MIT](LICENSE)

---

<p align="center">
  Made by <a href="https://github.com/ioanbitza">Ioan Bitza</a> · <a href="https://github.com/ioanbitza">ASTRALBYTE</a>
</p>
