<p align="center"><img src="docs/icon.png" width="128" height="128" alt="Find Empty Folders X icon"></p>

<h1 align="center">Find Empty Folders X</h1>
<h3 align="center">Find empty folders on your Mac, including those that only hold invisible files, and move them to the Trash safely.</h3>

<p align="center">
  <a href="https://github.com/lehenandmartin/FindEmptyFoldersX/releases"><img src="https://img.shields.io/github/v/release/lehenandmartin/FindEmptyFoldersX" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lehenandmartin/FindEmptyFoldersX" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" alt="macOS 26 or later">
</p>

---

Folders left empty by uninstalled apps, old projects or synced drives pile up, and many of them aren't really empty: they hold a `.DS_Store` or another invisible file, so the Finder never shows them as empty. Find Empty Folders X finds them all and lets you clear them out in one go.

It is a modernized rewrite, in Swift and SwiftUI, inspired by [Find Empty Folders](https://www.tempel.org/FindEmptyFolders) by Thomas Tempelmann.

## Features

- Drop folders on the window or the Dock icon; the scan runs in the background and can be stopped at any time.
- Folders that only contain invisible files (`.DS_Store`, `Icon`, `._*`…) count as empty; nested empty folders are grouped under their parent.
- Safe by design: symbolic links, other volumes, system folders and packages are left alone, unreadable folders count as not empty, and each folder is checked again right before it is moved.
- Moves to the Trash, never deletes: ⌘Z puts everything back.
- Inspector, Quick Look, Show in Finder, sortable table, Dock badge and notification when a long scan ends.
- English and French, light and dark mode.

## Requirements

- macOS 26 or later.

## Installation

1. Download the latest `.zip` from the [Releases](https://github.com/lehenandmartin/FindEmptyFoldersX/releases) page, unzip it and move **Find Empty Folders X** to your Applications folder.
2. The app isn't notarized by Apple, so macOS blocks it on first launch. Sign it locally once, in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Find Empty Folders X.app"
   codesign --force --deep --sign - "/Applications/Find Empty Folders X.app"
   ```

   The first command removes the "downloaded from the Internet" flag, the second signs the app for your Mac only.
3. To scan protected folders (Mail, Safari…), give the app Full Disk Access in System Settings → Privacy & Security.

## Building

Requires Xcode 26 or later. Open `FindEmptyFoldersX.xcodeproj` and run (⌘R), or:

```bash
xcodebuild -project FindEmptyFoldersX.xcodeproj -scheme FindEmptyFoldersX -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build build
```

The app, universal (Apple silicon and Intel), is written to `build/Build/Products/Release/`.

## About

This project was built with the assistance of [Claude](https://claude.ai), under the author's direction and review.

## License

[MIT](LICENSE) — © 2026 Martin Le Hénand
