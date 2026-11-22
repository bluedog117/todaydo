# todaydo

A local-first macOS activity tracker built with SwiftUI and SQLite. Track foreground apps and browser domains, review your time, record offline activities, and use a Pomodoro timer from the menu bar.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with a Swift toolchain compatible with Swift tools version 5.9 or later
- No third-party runtime dependencies

## Build

```sh
./build.sh
```

The script runs 31 core checks, builds the release executable, packages `build/todaydo.app`, and signs it with an ad-hoc signature. A full Xcode installation is not required. The app is not notarized.

To install the resulting app:

```sh
./build.sh install
```

This replaces an existing `/Applications/todaydo.app`. It does not install or modify a differently named application. For stable development signing, supply your own code-signing identity:

```sh
SIGN_IDENTITY="Your Development Identity" ./build.sh
```

Ad-hoc rebuilds may cause macOS to request Calendar or Automation permission again. Public source availability does not imply Apple notarization.

## Features

- Foreground app tracking with idle detection, media-playback awareness, and lock/sleep handling
- Optional browser domain classification for Safari and Chromium-based browsers
- Daily timeline with range editing, manual entries, splitting, and undo
- Weekly summaries, monthly heatmaps, long-term trends, and focus statistics
- App, domain, time-of-day, project, category, and workday rules
- Pomodoro timer with short/long breaks and macOS system alert sounds
- Stand, goal, activity-limit, and time-awareness reminders
- Adjustable interface scale, CSV export, local snapshots, and optional iCloud Drive backups
- Optional project-event synchronization to a dedicated Calendar

## Privacy and permissions

Activity records live in `~/Library/Application Support/todaydo/`, including `todaydo.sqlite` and local snapshots. This repository contains source code and synthetic self-checks, not activity history, databases, snapshots, signing certificates, or credentials.

Browser inspection briefly reads the current tab URL in memory to extract its domain. Full URLs, window titles, and typed text are not saved. Supported browsers skip private/incognito windows. Firefox receives app-level tracking only. Browser tracking requires macOS Automation permission.

Notifications require notification permission. Calendar integration requests full Calendar access to create, update, and remove managed project events. Optional iCloud backup stores unencrypted SQLite snapshots in the user's iCloud Drive; it is disabled by default. No custom analytics or telemetry service is included. This is a non-sandboxed desktop app; review the source and enable only the integrations you need.

The app uses its own bundle identifier (`app.todaydo.desktop`), settings keys, data folder, and Calendar name. It does not automatically import another app's data.

## Source layout

```text
Sources/TodaydoCore/  SQLite storage, classification, statistics, and undoable edits
Sources/Todaydo/      SwiftUI interface, activity capture, reminders, backups, Calendar
Sources/SelfTest/     Synthetic core checks
Resources/           Application metadata and signing entitlements
```

Run core checks independently with `swift run todaydo-selftest`.

## Current limitations

Calendar access uses full permissions. Daily summaries are computed from indexed sessions rather than a separate aggregate table. Reminders and preferences use UserDefaults. Activity polling uses a fixed interval. iCloud snapshots do not have app-level encryption. Floating panels do not independently detect every presentation or meeting state. Core self-checks do not verify real-world permission dialogs, browser integration, or multi-device iCloud behavior.
