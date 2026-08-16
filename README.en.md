# Too Much Chrome

> [中文](README.md) · [日本語](README.ja.md) · [Website](https://acerola-1.github.io/too-much-chrome/)

<p align="center">
  <img src="docs/images/icon.png" width="132" alt="Too Much Chrome icon">
</p>

<p align="center">
  <strong>See how many web-engine apps are hiding on your Mac.</strong>
</p>

<p align="center">
  Too Much Chrome scans every Chromium / WebView app on your macOS — Electron, CEF, NW.js,
  Tauri, Wails, and full browsers like Chrome, Edge, and Brave — then measures how much
  storage they take and how current their engines are. The name is a joke. The scan is serious.
</p>

<p align="center">
  <a href="https://github.com/Acerola-1/too-much-chrome/releases/latest"><strong>Download Latest</strong></a> ·
  <a href="https://acerola-1.github.io/too-much-chrome/"><strong>Website</strong></a> ·
  <a href="#highlights">Highlights</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#requirements">Requirements</a> ·
  <a href="#build">Build</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-M%20series-2ECC71?style=flat-square&logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square">
  <img alt="SwiftPM" src="https://img.shields.io/badge/SwiftPM-5.9-orange?style=flat-square&logo=swift">
</p>

## Screenshots

### Main Scan View

A floating glass toolbar and the report panel live on the same line: the grid reveals apps one
by one as they are found — the scanline light bar is real scan progress — while the right panel
sums up the total count, storage split, a type-distribution donut chart, a top-5 ranking, and
version health.

<p align="center">
  <img src="docs/images/app-hero-light.png" width="720" alt="Too Much Chrome main scan view">
</p>

## Highlights

### Real Scanning

Enumerates top-level `.app` bundles in `/Applications` and `~/Applications`. Electron / CEF /
NW.js are identified by dual signals — `Contents/Frameworks` directory names and plist Bundle
IDs — at near 100% accuracy: renamed builds (e.g. QQNT.framework) still keep
`com.github.Electron.framework` as a second signal. Tauri / Wails use Bundle ID /
resource-directory keywords plus build-path signatures in the main binary, honestly marked as
experimental.

### Storage Statistics

Recursive allocated size of the app bundle, plus `~/Library` user data (Application Support /
Caches / Containers / WebKit / Saved Application State / Logs), matched by bundle ID and app
name with deduplication.

### Version Health

Five-tier status (green → red) judged against an online baseline from official sources —
Electron via npm registry, Chromium via Google VersionHistory, Tauri via crates.io, Wails via
Go module proxy. The baseline caches for 24 hours, falls back to cached values per source, and
finally to built-in anchors — fully usable offline.

### Scanline Intro

A photocopier-style scanline bound to real scan progress — the light bar position is the
progress, and icons unblur one by one as they are discovered. The animation is skipped when
"Reduce Motion" is enabled.

### Report Panel & Detail Popover

Click any app to see its storage breakdown and install path, reveal it in Finder with one
click; ranking rows and grid icons highlight in sync, and `⌘R` rescans anytime.

### Native Swift, One-shot Task

Built with Swift / SwiftUI. Liquid Glass is enabled automatically on macOS 26 (falling back
to frosted materials on older systems). Scanning runs on background threads — the main thread
only renders results. Scan and go, no resident processes.

## Installation

1. Download the latest `.dmg` from [Releases](https://github.com/Acerola-1/too-much-chrome/releases/latest)
2. Open the DMG and drag Too Much Chrome into the Applications folder
3. Launch it from Launchpad or Applications; the first scan begins automatically

The app is notarized by Apple and opens directly after download.

## Requirements

- macOS 14 or later (Liquid Glass on macOS 26+)
- Apple Silicon (M-series chips, arm64 only — no Intel build)

## Build

SwiftPM project — open `Package.swift` in Xcode, or use the CLI:

```bash
./launch.sh            # Build the .app and launch (runs scripts/build-app.sh dev)
./launch.sh cli        # Build and run the headless scan CLI (tmc-scan)
swift build            # Compile all targets
swift test             # Unit tests
swift run tmc-scan --online   # Headless scan (online version baseline)
```

Distribution (Developer ID signing + Apple notarization + DMG) goes through `scripts/build-app.sh`:

```bash
./scripts/build-app.sh release    # Assemble .app + Developer ID signing (hardened runtime + timestamp)
./scripts/build-app.sh notarize   # Submit to Apple notarization and staple the ticket
./scripts/build-app.sh dmg        # Build and notarize the DMG (distribution artifact)
```

Releases are driven by `scripts/release.sh`: bump the version → generate release notes →
merge into main → tag → GitHub Actions builds, signs, notarizes, and publishes the Release
(see `.github/workflows/release.yml`).

## Star History

<p align="center">
  <a href="https://star-history.com/#Acerola-1/too-much-chrome&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Acerola-1/too-much-chrome&type=Date&theme=dark" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Acerola-1/too-much-chrome&type=Date" />
      <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Acerola-1/too-much-chrome&type=Date" width="720" />
    </picture>
  </a>
</p>

<p align="center">
  If this project helps you, a ⭐ would mean a lot for continued maintenance.
</p>

## License

This project is dual-licensed under **GNU AGPL-3.0**:

- **Open-source use**: The source is public and may be freely viewed, modified, and distributed
  under the [AGPL-3.0](LICENSE). As required by the AGPL, any derivative work — including
  software offered as a network service — must also release its complete source under AGPL-3.0.
- **Commercial use**: To use this project in a commercial product **without complying with the
  AGPL's copyleft obligations** (e.g. closed-source distribution or paid distribution without
  publishing source), you **must obtain a commercial license**. Open an issue or contact the
  author via [GitHub](https://github.com/Acerola-1/too-much-chrome).

Copyright © 2026 Acerola. All rights reserved.

### Third-Party Components

The only third-party dependency is **Sparkle** (auto-update framework) — MIT-style
license; everything else uses system frameworks (SwiftUI / AppKit / Foundation).
