# Privacy and permissions

Activity data is stored locally in `~/Library/Application Support/todaydo/`. The source repository contains no activity database or snapshots. No custom analytics or telemetry service is included.

| Capability | Access and data handling |
|---|---|
| App activity | Records foreground app identity and timing |
| Browser domains | Optional Automation access; reads the active URL in memory and saves its domain, not the full URL |
| Calendar | Optional full access to create, update, and remove managed project events |
| Notifications | Optional notification permission for reminder delivery |
| iCloud Drive | Optional unencrypted SQLite snapshots; disabled by default |

Window titles and typed keyboard content are not recorded. Private/incognito windows are skipped by supported browser integrations; Firefox receives app-level tracking only. This does not make a device-wide privacy guarantee about other software or the operating system.

Device names identify backups at runtime. Exports, snapshots, project names, and labels may contain personal information. Review them before sharing. The application is non-sandboxed; enable integrations according to your needs.
