<div align="center">

<img src="assets/macshelf-logo.svg" alt="MacShelf logo" width="140">

# MacShelf

**A clipboard shelf that lives in the menu bar — text and images, searchable, keyboard-first.**

[**Download the latest release →**](https://github.com/burakboduroglu/macshelf/releases/latest)

[![Release](https://img.shields.io/github/v/release/burakboduroglu/macshelf?style=flat-square)](https://github.com/burakboduroglu/macshelf/releases)
[![License](https://img.shields.io/github/license/burakboduroglu/macshelf?style=flat-square)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/burakboduroglu/macshelf?style=flat-square)](https://github.com/burakboduroglu/macshelf/commits)

![Swift](https://img.shields.io/badge/Swift-6-000?style=flat-square&logo=swift)
![SwiftUI](https://img.shields.io/badge/SwiftUI-AppKit-000?style=flat-square&logo=swift)
![SwiftData](https://img.shields.io/badge/SwiftData-persistence-000?style=flat-square&logo=apple)
![macOS](https://img.shields.io/badge/macOS-14+-000?style=flat-square&logo=apple)
![Homebrew](https://img.shields.io/badge/Homebrew-cask-000?style=flat-square&logo=homebrew)

</div>

---

macOS remembers exactly one thing you copied. MacShelf keeps the rest: a menu bar popover holding your recent text and images, searchable, navigable entirely from the keyboard, and closed again in a keystroke. It is a small native app — no Electron, no menu bar clutter, no account.

## What it is

Press `Cmd+Shift+V` anywhere and a popover drops from the menu bar with your clipboard history. Type to filter it, walk it with the arrow keys, press Return to put an item back on the clipboard. The popover stays open while you work, so collecting three snippets is three keystrokes rather than three round trips.

Items are text or image. Images are re-encoded to PNG, thumbnailed in the row, and deduplicated by content hash, so screenshotting the same window twice does not fill the list. Pin the ones you keep reaching for and they survive pruning.

The design goal was restraint: it should feel like part of the system, not an app demanding attention. There is no Dock icon, no window, no onboarding.

## Highlights

|     | Feature | How it works |
| --- | ------- | ------------ |
| ⌨️ | **Keyboard-first** | Arrows move the cursor, `Return` copies, `⌫` deletes, `Space` previews. The mouse is optional throughout. |
| 📋 | **Text and images** | Images decode from pasteboard types, file URLs and AppKit payloads, then normalise to PNG with dimensions and a SHA-256 hash. |
| 🔁 | **Copy without closing** | Selecting a row copies it and confirms in place for two seconds, so several items can be collected in one visit. |
| 🔒 | **Password managers stay out** | Honours the `nspasteboard.org` concealed / transient markers, and tracks which app held focus across the whole polling window rather than sampling it once. |
| 📌 | **Pinning** | Pinned rows sort to the top and are never touched by history pruning. |
| 🗜️ | **The store stays small** | Oversized copies are skipped, and dead SQLite pages are vacuumed at launch — a store bloated to 6.5 MB came back down to 475 KB. |
| 🧭 | **Knows where it came from** | Each entry records the app that owned the copy, shown in the preview card. |
| 🪶 | **Small** | A 3.8 MB app bundle over roughly 1,900 lines of Swift, with one third-party dependency. |

## Install

**Homebrew** — the tap carries the cask:

```bash
brew tap burakboduroglu/macshelf
brew install --cask macshelf
```

```bash
brew update && brew upgrade --cask macshelf   # later
```

**Direct download** — grab `MacShelf-<version>.dmg` from [Releases](https://github.com/burakboduroglu/macshelf/releases), open it, drag `MacShelf.app` into Applications.

Requires **macOS 14** or newer.

> **Accessibility is optional.** MacShelf copies to the clipboard without it. Grant it only if you want *Paste into frontmost app*, which synthesises `Cmd+V` — that one action needs the permission, nothing else does.

## Keyboard

| Key | Action |
| --- | ------ |
| `Cmd+Shift+V` | Show or hide the popover, from anywhere. Rebindable in Settings. |
| `↑` `↓` | Move the cursor |
| `Return` | Copy the selected item |
| `Cmd+1` … `Cmd+9` | Copy by position |
| `Space` *(hold)* | Preview the selected item |
| `⌫` | Delete the selected item |
| `Cmd+⌫` | Delete even while a search is typed |
| `Esc` | Closes the preview, then the search, then the popover |
| Right-click | Pin, paste into the frontmost app, delete |

Typing anywhere filters the list — the search field always has focus, so there is nothing to click into first.

## Stack

**Swift 6** targeting **macOS 14**, built with SwiftPM. The UI is **SwiftUI** hosted inside **AppKit**: a `MenuBarExtra` cannot be opened programmatically, which a hotkey-driven app requires, so `AppDelegate` owns an `NSStatusItem` and an `NSPopover` directly. History lives in **SwiftData**, backed by SQLite.

The only third-party dependency is [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) for the recordable global hotkey.

## Build

```bash
git clone https://github.com/burakboduroglu/macshelf.git
cd macshelf
scripts/build.sh
```

| Script | What it does |
| ------ | ------------ |
| `scripts/build.sh` | Compiles, assembles `build/MacShelf.app`, ad-hoc signs it |
| `scripts/build.sh --run` | Same, then relaunches the app |
| `scripts/package-dmg.sh` | Writes `dist/MacShelf-<version>.dmg` with an `/Applications` shortcut |
| `open Package.swift` | Opens the package in Xcode — pick the `MacShelf` scheme, run on *My Mac* |

> **Xcode is required, not just the Command Line Tools.** The `@Model` macro compiles through `libSwiftDataMacros.dylib`, which ships inside `Xcode.app`; the CLT toolchain carries only three macro plugins and none of them is that one. Without Xcode the build fails at `Schema([ClipboardItem.self])`.

`swift run MacShelf` produces a bare executable rather than a bundle, so the status item and resources are missing. Use `scripts/build.sh`.

## How it works

`ClipboardMonitor` polls `NSPasteboard.general.changeCount` every 250 ms — macOS posts no notification for pasteboard changes, so comparing the counter is the supported approach. Polling can only ever see the last value of a burst, which is the one real limitation: copying ten things in half a second records a few of them, not all ten.

**Attribution.** `changeCount` reports that the pasteboard moved *somewhere* in the last interval, never when. Reading `frontmostApplication` at poll time therefore credits whichever app happens to be focused by then. MacShelf instead watches `didActivateApplicationNotification` and keeps every app that held focus during the window: the ignore list is checked against all of them, and the entry is attributed to the first.

**Deduplication.** Text matches exactly, images match on PNG hash. A repeat copy is not a new row — it moves the existing one to the top, so the thing you just used does not sit at the bottom waiting to be pruned.

**Storage.** SwiftData writes to `~/Library/Application Support/MacShelf/MacShelf.store`. Text over 256,000 characters and images over 16 MB are skipped: `text` has no external storage, so a large copy lands inline in SQLite, and deleting it later only parks its pages on the free list. Those pages are reclaimed by an incremental vacuum and a WAL checkpoint at launch, before the store is opened.

**Pasting.** `PasteService` writes to the pasteboard and, when Accessibility is granted, posts a synthetic `Cmd+V` through `CGEvent`. Its own writes carry the auto-generated marker so they are never captured back into the history.

## Privacy

Everything stays on the machine. There is no network call except the manual update check against the GitHub Releases API.

Copies are skipped when the pasteboard carries `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType` or `org.nspasteboard.AutoGeneratedType` — the [nspasteboard.org](http://nspasteboard.org) convention that 1Password, Bitwarden and others set on secrets — or when a known password-manager bundle ID held focus while the copy happened.

## Project layout

```
Sources/MacShelf/
├─ App/
│  ├─ MacShelfApp.swift        SwiftUI entry point and Settings scene
│  └─ AppDelegate.swift        Status item, popover, hotkey, monitor lifecycle
├─ Models/
│  └─ ClipboardItem.swift      SwiftData model for text and image entries
├─ Services/
│  ├─ ClipboardMonitor.swift   Polling, decoding, dedupe, pruning
│  ├─ StoreService.swift       Store location, migration, SQLite compaction
│  ├─ PasteService.swift       Pasteboard writes and the synthetic Cmd+V
│  ├─ PermissionsService.swift Accessibility trust check
│  ├─ HotkeyManager.swift      Global shortcut registration
│  └─ UpdateService.swift      Manual release check
├─ Views/
│  ├─ MenuView.swift           Search, list, key capture, preview state
│  ├─ ItemRow.swift            A single history row
│  ├─ DetailsCard.swift        The Space preview card
│  └─ SettingsView.swift       General, Shortcuts and Privacy tabs
└─ Resources/                  Info.plist, entitlements, asset catalog
```

## Updates

**Check for Updates…** in the footer menu compares the installed version against the latest GitHub Release and, if there is a newer one, downloads its DMG and opens the installer. MacShelf never replaces itself silently; signed in-app updates through Sparkle are the intended next step.

Local builds are ad-hoc signed. Anything distributed should be signed and notarized with an Apple Developer ID.

## License

Released under the [MIT License](LICENSE).

<div align="center">
<sub>Built by <a href="https://github.com/burakboduroglu">Burak Boduroğlu</a></sub>
</div>
