<div align="center">

# todaydo

**Know where your day goes. Keep your activity data under your control.**

A native, local-first macOS activity tracker with timelines, focus insights, and a menu bar Pomodoro timer.

[![macOS](https://img.shields.io/badge/macOS-14%2B-111827?logo=apple)](#compatibility)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](Package.swift)
[![Release](https://img.shields.io/github/v/release/bluedog117/todaydo)](https://github.com/bluedog117/todaydo/releases)
[![Issues](https://img.shields.io/github/issues/bluedog117/todaydo)](https://github.com/bluedog117/todaydo/issues)
[![Stars](https://img.shields.io/github/stars/bluedog117/todaydo?style=flat)](https://github.com/bluedog117/todaydo/stargazers)

[Get started](#get-started) · [User guide](docs/USER_GUIDE.md) · [Documentation](#documentation) · [Report a bug](https://github.com/bluedog117/todaydo/issues/new/choose)

</div>

## Features

| Area | What you can do |
|---|---|
| Activity tracking | Track foreground apps, idle time, screen lock/sleep, and supported browser domains |
| Timeline | Review today, select time ranges, add offline activity, split records, edit, and undo |
| Insights | Explore weekly totals, monthly heatmaps, long-term trends, and activity fragmentation |
| Rules and projects | Classify by app, domain, or time of day; assign projects and override workdays |
| Focus | Run a Pomodoro timer with short/long breaks, pause/resume, and system sounds |
| Reminders | Configure stand, goal, limit, and time-awareness reminders |
| Data | Export CSV, restore local snapshots, and optionally back up to iCloud Drive |
| Calendar | Optionally sync project activity to a dedicated calendar |

## Compatibility

- **macOS 14 or later**; English interface.
- Swift toolchain compatible with **Swift tools 5.9 or later**; Command Line Tools are sufficient.
- No third-party runtime dependencies. SQLite comes from macOS.
- Browser-domain support targets Safari and Chromium-based browsers. Firefox is app-level only.

## Get started

```sh
git clone https://github.com/bluedog117/todaydo.git
cd todaydo
./build.sh
```

Open `build/todaydo.app`. The app lives in the menu bar and opens its main window on first launch.

To install to `/Applications/todaydo.app`, run `./build.sh install`. This replaces an existing todaydo installation. See the [build guide](docs/BUILD.md) for signing and troubleshooting.

### Downloads

[Releases](https://github.com/bluedog117/todaydo/releases) provide versioned source snapshots and release notes. Build the app locally using the instructions above. A notarized, ready-to-install binary is not currently provided; do not mistake a source archive for a packaged application.

## Privacy

Records are stored in `~/Library/Application Support/todaydo/`. Full URLs, window titles, and typed keyboard content are not saved. Browser URLs exist briefly in memory to extract the domain. Supported browser integrations skip private/incognito windows.

Calendar synchronization, browser Automation, notifications, and iCloud backups are separate integrations. iCloud snapshots are unencrypted and disabled by default. The app is non-sandboxed and ad-hoc signed by default. Read [Privacy and permissions](docs/PRIVACY.md) before enabling integrations.

The repository contains source and synthetic self-checks, not activity history, device backups, signing material, or credentials.

## Documentation

| Document | Contents |
|---|---|
| [User guide](docs/USER_GUIDE.md) | First launch, views, tracking, focus, backups, and Calendar |
| [Build guide](docs/BUILD.md) | Requirements, installation, signing, core checks, troubleshooting |
| [Architecture](docs/ARCHITECTURE.md) | Modules, storage boundaries, implementation limits |
| [Privacy](docs/PRIVACY.md) | Permissions, local data, browser behavior, iCloud |
| [Changelog](CHANGELOG.md) | Version history |
| [Contributing](CONTRIBUTING.md) | Development and pull request expectations |
| [Security](SECURITY.md) | Sensitive reports and data-sharing precautions |

## Validation and limits

The initial public version passed **31 synthetic core checks**, a release build, and local signature verification. The Today and Settings views were opened to check English text. These checks do not establish real-world browser authorization, Calendar synchronization, or multi-device iCloud reliability.

Polling uses a fixed interval; daily totals are aggregated from indexed sessions. Preferences and reminder rules use UserDefaults. iCloud snapshots have no app-level encryption, and floating panels do not independently detect every meeting or presentation. See [architecture notes](docs/ARCHITECTURE.md).

## Contributing and support

Use the [bug report or feature request templates](https://github.com/bluedog117/todaydo/issues/new/choose). Include reproducible steps and synthetic examples. Never upload personal activity databases or private screenshots. See [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md).

## License

[MIT License](LICENSE) · Copyright © 2026 todaydo contributors.

## Star history

[![Star History Chart](https://api.star-history.com/svg?repos=bluedog117/todaydo&type=Date)](https://www.star-history.com/#bluedog117/todaydo&Date)
