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

A lightweight native macOS menu bar utility that displays the current Codex account's **rolling five-hour quota**, **weekly quota**, and both reset times.

> This is an independent community project. It is not affiliated with, endorsed by, or sponsored by OpenAI.

## Features

- Shows the rolling five-hour quota directly in the menu bar
- Shows five-hour and weekly usage/reset details in the menu
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
`account/rateLimits/read`, and parses both the 300-minute rolling five-hour
window and the 10,080-minute weekly window.

- Does not directly read `~/.codex/auth.json`
- Does not copy or upload Codex tokens
- Local Codex mode contains no analytics, telemetry, or third-party network requests
- In local Codex mode, all quota access is handled locally by the Codex CLI

The Codex CLI app-server is experimental, so future protocol changes may require updates.

## Development

```bash
swift test
swift run CodexWeekly --probe
```

Project structure:

- `CodexQuotaClient.swift`: Codex app-server communication
- `QuotaSnapshot.swift`: five-hour and weekly quota parsing and window selection
- `AppDelegate.swift`: menu bar UI, refresh scheduling, and launch at login
- `QuotaParserTests.swift`: protocol response parsing tests

## License

[MIT](LICENSE)

## Sub2API allocated allowance (optional)

Choose **配置 Sub2API…** in the menu, enter the HTTPS Base URL and API Key,
then **保存并查询**. The key is stored in macOS Keychain, scoped to the normalized
endpoint, never in preferences or logs. Only the configured server receives it
via `GET /v1/usage`. Redirects, HTTP URLs, browser cookies and response caching
are disabled. This optional mode makes a third-party request, unlike local Codex mode.

The menu shows daily and weekly **allocated USD allowances**, used/limit/remaining,
and refresh time; the menu bar always shows daily remaining percentage (unknown if absent). Subscription
allowances may be shared across keys in that subscription; these are not the
upstream 20x account limits. Refresh is every five minutes or manually. Missing
windows are not zero. A combined balance is not presented as weekly quota.
Reset times are only displayed when explicitly returned, otherwise unknown.
Errors clear quota values and show the last successful update time when available.
Use **切换到 Codex 本地额度** to return to the unchanged local Codex mode.

Only `subscription.daily_usage_usd/daily_limit_usd`, weekly equivalents, and
`rate_limits` entries with `window: 1d/7d` are mapped. Different deployments may
omit subscription details; verify with your platform before relying on values.
Never paste your key into chat, git, or a bug report.

The source-switch menu item always offers the other source. Switching from local to Sub2 reuses the saved Keychain key without reopening setup; fetch errors do not prevent switching back.
