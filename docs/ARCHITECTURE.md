# Architecture

`TodaydoCore` contains SQLite persistence, the classification model, logical-day calculations, statistics, and undoable edits. It links the system SQLite library and has no third-party runtime dependency.

`Todaydo` contains the SwiftUI app, foreground activity tracker, browser AppleScript adapter, notification/reminder engine, Calendar integration, and snapshot management. Preferences and reminder rules use UserDefaults. Activity records use SQLite.

`Sources/SelfTest` exercises the core with synthetic records and temporary databases.

## Data boundaries

- Bundle identifier: `app.todaydo.desktop`.
- Local storage: `~/Library/Application Support/todaydo/`.
- Optional iCloud Drive snapshots use a separate todaydo folder and per-device records.
- Browser URLs exist briefly in memory to extract hostnames; persisted records store domains.
- Calendar and iCloud integrations are optional. There is no custom analytics endpoint.

## Implementation limits

Polling uses a fixed interval; daily totals are calculated from indexed sessions rather than a separate aggregate table. iCloud snapshots have no app-level encryption. The app is not sandboxed. Code-signing identity stability affects macOS permission persistence.
