# Codex Weekly

<p align="center">
  <strong>English</strong> | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="Assets/AppIcon-1024-v2.png" width="160" alt="Codex Weekly icon">
</p>

<p align="center">
  <a href="https://github.com/Pototoooo/codex-weekly/actions/workflows/ci.yml"><img src="https://github.com/Pototoooo/codex-weekly/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Pototoooo/codex-weekly/releases/latest"><img src="https://img.shields.io/github/v/release/Pototoooo/codex-weekly" alt="GitHub release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Pototoooo/codex-weekly" alt="MIT License"></a>
</p>

A lightweight native macOS menu bar utility that displays the **weekly quota remaining** and reset time for the current Codex account.

> This is an independent community project. It is not affiliated with, endorsed by, or sponsored by OpenAI.

## Features

- Shows the remaining weekly quota directly in the menu bar
- Refreshes every 60 seconds, with manual refresh support
- Automatically adapts to light, dark, and fullscreen menu bar backgrounds
- Uses a warning symbol for low quota instead of relying on fixed colors
- Shows the used percentage and next reset time
- Optional launch at login
- Native multi-resolution macOS app icon
- Does not read, copy, or upload `~/.codex/auth.json`; quota data is retrieved through the local Codex CLI `app-server`

## Installation

1. Download `Codex-Weekly-macOS.zip` from the [latest release](https://github.com/Pototoooo/codex-weekly/releases/latest).
2. Extract the archive.
3. Move `Codex Weekly.app` to `/Applications`.
4. Launch the app. It runs in the menu bar and does not appear in the Dock.
5. If macOS blocks the non-notarized community build, right-click the app in Finder and choose **Open**.

Codex Desktop or Codex CLI must already be installed and signed in.

## Build and Verify

```bash
./build-app.sh
.build/release/CodexWeekly --probe
```

Build artifacts are written to `dist/`. Building requires macOS 13+ and Xcode/Swift 6.

## How It Works

The app starts the local Codex CLI with `app-server --stdio`, calls
`account/rateLimits/read`, and displays the quota window whose duration is
10,080 minutes (one week).

- Does not directly read `~/.codex/auth.json`
- Does not copy or upload Codex tokens
- Contains no analytics, telemetry, or third-party network requests
- All quota access is handled locally by the Codex CLI

The Codex CLI app-server is experimental, so future protocol changes may require updates.

## Development

```bash
swift test
swift run CodexWeekly --probe
```

Project structure:

- `CodexQuotaClient.swift`: Codex app-server communication
- `QuotaSnapshot.swift`: weekly quota parsing and window selection
- `AppDelegate.swift`: menu bar UI, refresh scheduling, and launch at login
- `QuotaParserTests.swift`: protocol response parsing tests

## License

[MIT](LICENSE)
