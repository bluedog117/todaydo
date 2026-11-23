# User guide

## First launch

Open the built app. todaydo lives in the menu bar and opens its main window on first launch. Use the menu bar panel to open the window again, pause tracking, or control a focus session.

## Views

| View | Purpose |
|---|---|
| Today | Review a timeline, add offline activity, edit a selected range, and undo edits |
| This week | Compare daily totals and category usage |
| Month | Review activity in a calendar heatmap |
| Trends | Explore longer-term usage and daily rhythm |
| Focus | Review fragmentation and control the Pomodoro timer |
| Rules and projects | Manage app/domain/time rules, projects, categories, and workday overrides |
| Settings | Configure idle detection, reminders, interface scale, integrations, snapshots, and export |

## Tracking and classification

Automatic recording follows foreground applications. Optional browser support extracts domains from supported browsers; Firefox is app-level only. Private/incognito windows are skipped by supported browser integrations. Time-based category rules take precedence over domain and app defaults. Manually edited activity is not automatically reclassified.

Drag over the Today timeline to select a range. You can change categories, assign projects, label, or delete selected activity. Use Undo for supported edits. Offline prompts let you account for time away from the computer.

## Focus and reminders

Start a Pomodoro from the menu bar or Focus view. Pause, resume, extend by five minutes, or move to a break. Short and long breaks and system alert sounds are configurable. Notifications and corner panels are separate delivery methods; floating panels do not independently detect every meeting or presentation state.

## Backups and export

Local data: `~/Library/Application Support/todaydo/`. Snapshots can restore an earlier database, replacing current content. Export records as CSV from Settings. Optional iCloud Drive backups are unencrypted SQLite snapshots and disabled by default. Keep personal exports and backups outside public repositories.

## Calendar

Create a project and assignment rules before enabling Calendar sync. todaydo creates a dedicated calendar and needs full Calendar access to manage its events. Nearby project activity is merged and written after a delay.
