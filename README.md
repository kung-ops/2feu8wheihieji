# APK Sandbox (iOS 12+)

An iOS app that opens Android `.apk` files and **runs simple Android apps** on an
iPhone, using a small Dalvik bytecode interpreter written in Swift. It works on
iOS 12, so it runs on an iPhone 6.

## What it does
1. **Pick an APK.** Tap **+** to choose one from Files or iCloud Drive, or use
   **Open in → APK Sandbox** from Safari, Mail or Files. You can also drop APKs
   into the app's folder in Finder or iTunes File Sharing.
2. **Inspect it.** You see the icon, name, package, version, SDK levels,
   permissions, activities and the decoded `AndroidManifest.xml`.
3. **Run it.** The launcher activity starts inside a sandbox:
   - The app's real Java/Kotlin bytecode (`classes*.dex`) runs in the built-in
     interpreter.
   - `res/layout/*.xml` is drawn with native iOS views. Supported widgets:
     TextView, Button, EditText, CheckBox/Switch, ImageView, SeekBar and
     ProgressBar, inside LinearLayout and other containers.
   - Click listeners, `android:onClick`, Toast, AlertDialog, Log and
     `System.out` (shown in the log console), SharedPreferences (saved
     between runs), Handler/postDelayed timers, `startActivity` between the
     app's own screens, and the Back button all work.

## Honest limits
This doesn't emulate Android, and nothing can run *every* APK on iOS. These
don't work:
- **Native code** (`lib/*.so`): games, Unity/Flutter/React Native apps, most
  emulators.
- OpenGL, WebView, RecyclerView/ListView, Fragments, Jetpack Compose UIs.
- Google Play services, networking, camera and sensors.

Big apps will show their info and a log of the parts that couldn't run. Small
apps work best: a hello-world, a counter, a calculator or a school project
built with Android Studio's "Empty Views Activity" template.

## Code layout
```
Sources/
  Apk/   ZipArchive, BinaryXML (AXML), ResourceTable (resources.arsc), DexFile, ApkPackage
  VM/    VM.swift (Dalvik interpreter), Framework*.swift (Android/Java library stubs),
         AndroidRuntime.swift (activities, views, Java string semantics)
  UI/    Library / ApkInfo / Run screens, LayoutInflater (Android XML → UIKit)
```

## Build the IPA (GitHub + Codemagic)
1. On https://codemagic.io, connect this repo and start the
   **apk-sandbox-ios** workflow. If you're building from a branch, pick that
   branch.
2. Codemagic runs `xcodegen` to create `ApkSandbox.xcodeproj`, builds with
   Xcode 15.4 (the last Xcode that targets iOS 12), and gives you an unsigned
   **`ApkSandbox.ipa`** as the build artifact.

## Install on your iPhone
The IPA is unsigned, so sign it with your **free Apple ID** using
**Sideloadly** (Windows/Mac) or **AltStore**: drag in `ApkSandbox.ipa`, sign in
and install. With a free account, apps have to be re-signed every 7 days.
