# Changelog

All notable changes to MacShelf are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Continuous integration: every push and pull request builds the app bundle,
  lints `Info.plist`, verifies the signature and checks that the version in the
  bundle matches the one in the source.
- A release workflow. Pushing a version tag packages the DMG, publishes the
  release with these notes, and prints the two lines the Homebrew cask needs.
- Community health files: a contributing guide, a code of conduct, a security
  policy, issue forms and a pull request template.
- A social preview card, and README screenshots of the popover and the copy
  confirmation.

### Changed

- `scripts/package-dmg.sh` runs the Finder styling pass under a watchdog and
  falls back to the default window layout rather than hanging, so it can
  package a DMG unattended.

### Fixed

- The install steps describe what Gatekeeper actually does on first launch,
  including the re-sign fallback that macOS 26 needs.

## [0.2.0] - 2026-09-02

### Fixed

- Deleting an item works. `delete` ran on a `ModelContext` of its own while the
  objects `@Query` hands back belong to the container's main context, so asking
  a context to delete an object it never registered failed silently. The
  monitor now shares the main context.
- Entries are capped, and re-copying something moves the existing row to the
  top instead of adding a duplicate.
- The store lives in its own directory and reclaims dead SQLite pages at
  launch; a store that had bloated to 6.5 MB came back down to 475 KB.
- Each entry records the app that owned the copy correctly.
- Packaging removes a stale app bundle before writing a new one, and the
  KeyboardShortcuts dependency points at upstream so a clean checkout resolves.

### Changed

- The history list became a copy palette: selecting a row copies it and
  confirms in place, and the popover stays open so several items can be
  collected in one visit.
- The logo was redrawn as a flat mark, and the README rewritten around install,
  use and build.

### Added

- Homebrew installation through the `burakboduroglu/macshelf` tap, and an MIT
  license.

## [0.1.0] - 2026-05-03

### Added

- First release: a menu bar popover holding recent clipboard text and images,
  searchable, navigable from the keyboard, shipped as a styled DMG.

[Unreleased]: https://github.com/burakboduroglu/macshelf/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/burakboduroglu/macshelf/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/burakboduroglu/macshelf/releases/tag/v0.1.0
