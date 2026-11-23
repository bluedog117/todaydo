# Building todaydo

## Requirements

macOS 14 or later and Xcode Command Line Tools with a Swift 5.9-compatible or newer toolchain. No third-party runtime dependencies are required.

```sh
git clone https://github.com/bluedog117/todaydo.git
cd todaydo
./build.sh
```

The build script runs 31 synthetic core checks, builds a release executable, packages `build/todaydo.app`, and verifies its ad-hoc signature.

```sh
./build.sh install
```

Installation replaces `/Applications/todaydo.app`. To use a stable signing identity, set `SIGN_IDENTITY="Your Development Identity"`. Ad-hoc rebuilds can reset macOS permissions. The app is not notarized.

## Core checks

```sh
swift run todaydo-selftest
```

Checks cover logical days, category priority, domain matching, editing, splitting, undo, aggregation, and SQLite backup/restore. They do not prove browser permissions, Calendar synchronization, or multi-device iCloud behavior.

## Troubleshooting

- Install Command Line Tools with `xcode-select --install` if Swift is missing.
- If Automation is denied, use System Settings → Privacy & Security → Automation. App-level tracking remains available.
- Calendar access is optional and requires full Calendar permission.
- For a fresh build, remove only this checkout's `.build/` and `build/` directories. Do not delete your activity database to fix a compiler error.
