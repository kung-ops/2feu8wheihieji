# Modern

A tiny UIKit iOS app that runs on **iOS 12** (iPhone 6 and up).
Shows a "Modern" title and a button that counts taps.

## Why it works on iPhone 6
- Deployment target is **iOS 12.0** (set in `project.yml`).
- Uses **UIKit** with a classic `AppDelegate` (no SceneDelegate — scenes are iOS 13+).

## Build it (GitHub + Codemagic)
1. Put these files in your GitHub repo (keep the folder layout):
   ```
   project.yml
   codemagic.yaml
   Sources/AppDelegate.swift
   Sources/ViewController.swift
   Sources/Info.plist
   Sources/LaunchScreen.storyboard
   ```
2. On https://codemagic.io, connect that repo and start a build of the
   **modern-ios** workflow.
3. Codemagic runs `xcodegen` (creates `Modern.xcodeproj`), then builds an
   **unsigned** `Modern.ipa` and offers it as a downloadable artifact.

## Put it on your iPhone 6
The build is unsigned, so sign it with your **free Apple ID** on a computer:
- **Sideloadly** (Windows/Mac) or **AltStore** — drag in `Modern.ipa`, enter
  your Apple ID, install. Free-account apps re-sign every 7 days.

## Change it
- Edit `Sources/ViewController.swift` to change what the screen shows.
- Push to GitHub → Codemagic rebuilds automatically.
