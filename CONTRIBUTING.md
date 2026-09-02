# Contributing

Thanks for looking. MacShelf is a small personal app, so the useful
contributions are usually small too: a bug you can reproduce, a rough edge in
the keyboard handling, a case the clipboard monitor gets wrong.

Before building anything substantial, open an issue and check the direction is
wanted. The app is deliberately narrow — a menu bar popover, a history, a
keyboard — and the easiest proposals to accept are the ones that keep it that
way.

## Getting started

```bash
git clone https://github.com/burakboduroglu/macshelf.git
cd macshelf
scripts/build.sh --run
```

**Xcode is required, not just the Command Line Tools.** The `@Model` macro
compiles through `libSwiftDataMacros.dylib`, which ships inside `Xcode.app`.
The CLT toolchain carries three macro plugins and none of them is that one, so
without Xcode the build fails at `Schema([ClipboardItem.self])`.

| Command | What it does |
| ------- | ------------ |
| `scripts/build.sh` | Compiles, assembles `build/MacShelf.app`, ad-hoc signs it |
| `scripts/build.sh --run` | Same, then relaunches the app |
| `scripts/package-dmg.sh` | Writes `dist/MacShelf-<version>.dmg` |
| `swift build --product MacShelf` | Compiles only — no bundle, so no status item |

`open Package.swift` opens the package in Xcode; pick the `MacShelf` scheme and
run on *My Mac*.

## Project layout

```
Sources/MacShelf/
├─ App/         SwiftUI entry point, status item, popover, hotkey wiring
├─ Models/      The SwiftData model
├─ Services/    Clipboard polling, store location, pasting, permissions, updates
├─ Views/       Search, list, rows, preview card, settings
└─ Resources/   Info.plist, entitlements, asset catalog
```

`AppDelegate` owns the long-lived objects. `ClipboardMonitor` is the heart of
the app: it polls the pasteboard, decides what to keep, and prunes. If you are
changing capture behaviour, that is the file.

## Testing by hand

There is no test target yet, so changes are verified by running the app. At a
minimum, after any change to capture or storage:

1. Copy some text — it appears at the top of the list.
2. Copy the same text again — the existing row moves to the top rather than
   duplicating.
3. Copy an image — it appears with a thumbnail and dimensions.
4. Select a row — it copies, the popover stays open, the badge clears after
   two seconds.
5. Press `⌫` on a row — it disappears and stays gone after a relaunch.

The store is a plain SQLite file, so `sqlite3 ~/Library/Application\
Support/MacShelf/MacShelf.store "select ZTEXT from ZCLIPBOARDITEM;"` is a fast
way to check what actually landed.

## Style

Match the file you are editing. Beyond that:

- Comments explain *why*, not *what*. If a line is surprising, say what made it
  necessary — the reasoning behind the polling window or the quarantine
  workaround is worth more than a restatement of the code.
- Keep `ClipboardMonitor` readable. It is the part most likely to grow warts.
- No new dependency without a reason in the pull request.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org):

```
feat: bump a re-copied entry to the top of the history
fix: share the container's main context with the monitor
docs: correct the install steps for Gatekeeper
chore: bump version to 0.2.0
refactor: ...   perf: ...   test: ...
```

Use the imperative mood in the subject line, keep it under ~72 characters, and
put the reasoning in the body when the change is not self-evident. No emoji —
the subject line should read the same in a terminal as on the web.

## Pull requests

`main` requires a pull request. Branch from it, keep the change focused, and
fill in the template — the checklist is short and each line is there because
something once slipped through it.

Screenshots are required for anything visual.

## Releasing

Releases are cut from a tag; the `Release` workflow does the rest.

1. Bump `CFBundleShortVersionString` in `Sources/MacShelf/Resources/Info.plist`.
2. Move the `Unreleased` entries in `CHANGELOG.md` under a new
   `## [x.y.z] - YYYY-MM-DD` heading and update the link definitions at the
   bottom.
3. Commit as `chore(release): bump version to x.y.z` and merge into `main`.
4. Tag the merge commit and push it:

   ```bash
   git tag -a vx.y.z -m "vx.y.z"
   git push origin vx.y.z
   ```

The workflow refuses the tag if it disagrees with `Info.plist` or if the
changelog has no section for it. Otherwise it packages the DMG, checks that it
mounts and that the app inside is signed, publishes a release with the
changelog section as its notes, attaches the DMG and its checksum, and prints
the `version` and `sha256` lines for the Homebrew cask into the run summary.
Copy those into `Casks/macshelf.rb` in
[`burakboduroglu/homebrew-macshelf`](https://github.com/burakboduroglu/homebrew-macshelf).

`scripts/package-dmg.sh` builds the same DMG locally. A Mac with a Finder
session also gets the styled window, which a CI runner cannot always produce —
the pass gives up after its watchdog rather than hanging the build.

## Reporting bugs

Use the [bug report form](https://github.com/burakboduroglu/macshelf/issues/new/choose)
and include your MacShelf version, your macOS version, and how you installed
it. If the app quits the instant you launch it, that is Gatekeeper rather than a
bug — see [the install section](README.md#install).

Security problems go through a [private advisory](SECURITY.md), never a public
issue.

## Code of conduct

Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).
