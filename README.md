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

Large apps can show their information, but cannot be assumed to run. Missing
DEX files, invalid launcher classes, and unsupported non-noop Android APIs now
report explicit errors. The Linux runner returns a failure if no app bytecode
was interpreted. Compatibility no-ops are still present, but are logged and
counted rather than hidden.

Small apps work best: a hello-world, a counter, a calculator or a school project
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
   Xcode 16.4, and gives you an unsigned **`ApkSandbox.ipa`** as the build
   artifact. Codemagic no longer has Xcode 15. Apple officially lists iOS 15
   as Xcode 16's minimum target, but sideloaded builds with an iOS 12.0 target
   still run on iOS 12.
3. Your iPhone should be on **iOS 12.2 or newer** (an iPhone 6 can update to
   12.5.7). Older iOS 12 versions don't include the Swift runtime.

## Install on your iPhone
The IPA is unsigned, so sign it with your **free Apple ID** using
**Sideloadly** (Windows/Mac) or **AltStore**: drag in `ApkSandbox.ipa`, sign in
and install. With a free account, apps have to be re-signed every 7 days.

## Optional PC Bridge (Windows + iOS 12)

APK selection and the **+** Files picker work exactly as before. The new **PC** button opens an optional, opt-in media bridge. It does not replace the APK interpreter or make all Android apps run.

1. On Windows, install Node.js 18 or later, open `PCBridge`, and double-click **`START-PC-BRIDGE.bat`**. The server runs using only standard Node.js modules; `npm install` is unnecessary.
2. Connect your Windows PC and your iPhone to the **same trusted Wi-Fi network**. Keep the BAT window open. In Windows Firewall, allow Node.js on **Private** networks only if prompted.
3. In the IPA, open **PC Bridge** from the main APK list or the Run screen. Enter the **PC address** (`http://192.168.x.x:8765`) and the **pairing key** printed in the BAT window, then tap **Connect to PC**.
4. **Take Photo with Camera** uses the iPhone camera. **Record Microphone** records on the iPhone for up to 60 seconds. iOS asks for camera/microphone permission, and **you must confirm Send to PC** before either file leaves the phone. The files appear in `PCBridge/received`.
5. To listen to PC sound through your iPhone, copy an **MP3, M4A or WAV** (up to 20 MB) into `PCBridge/pc-audio`, then tap **Play PC Audio** and select the file.
6. To stop PC Bridge, close its console window. To run bridge tests: `node PCBridge/test-server.js`.

**Privacy and compatibility:** This is plain HTTP on the trusted LAN, not encrypted HTTPS. The pairing key is generated anew on each server launch and is not saved in the IPA. Do **not** use it on public Wi-Fi or expose port 8765 to the internet. Your camera/mic are never started by the PC; you press the buttons and grant iOS permission. This feature supplies iOS-native camera/microphone functions and transfers audio/photos between devices. It does **not** implement arbitrary Android camera, `AudioRecord`, `MediaPlayer`, JNI/native-library, or other missing APIs within imported APKs.
