# APK Sandbox – a virtual Android phone for iPhone (iOS 12 & iOS 15)

An iOS app that **installs and runs simple Android apps (.apk)** on an iPhone.
It acts like a small virtual Android phone (Android 9, 1 GB RAM) with its own
package installer, home screen and ◁ ○ □ navigation keys. The apps' real
Java/Kotlin bytecode (`classes.dex`) runs in a Dalvik interpreter written in
Swift, and their layouts are drawn with native iOS views.

Made for an **iPhone 7 on iOS 15 or iOS 12**. It also runs on 1 GB iPhones
(iPhone 6 / 6 Plus, iPod touch 6) in a low-memory mode.

## What you get
- **Install like on Android.** Tap **Install** on the home screen (or open an
  `.apk` with "APK Sandbox" from Safari, Mail, Files or AirDrop). The package
  installer shows the app, its permissions and any compatibility problems,
  then installs it. Installing a newer version updates the app and keeps its
  data.
- **Home screen.** Installed apps appear with their own icons. Tap to open.
  Touch and hold for **App info**, **Force stop** and **Uninstall**.
- **App info.** Storage used, **Clear storage**, **Clear cache**, version,
  permissions, the decoded `AndroidManifest.xml`, and **Share APK**.
- **Running apps** get an Android app bar and navigation bar:
  ◁ Back (the app's own `onBackPressed`), ○ Home (the app pauses and stays in
  the background on 2 GB+ iPhones), □ for the log, Restart, Close and Force stop.
- **Downloads.** `.apk` files you put in Files › On My iPhone › APK Sandbox.
  Install them, or run one without installing it.
- **Settings.** The virtual phone (Android 9, 1 GB RAM, memory per app) and
  the real iPhone (model, iOS version, RAM, memory in use), plus PC Link.

## Game features (ideas from Husk)
- **Simple 2D games and drawing apps run.** Views that draw in
  `onDraw(Canvas)` (shapes, text, paths, bitmaps, transforms) are drawn with
  CoreGraphics at up to about 40 frames a second, and touches reach
  `onTouchEvent` / `OnTouchListener` as `MotionEvent`s.
- **Game settings per app** (App info): a custom name, portrait / landscape /
  "as the app asks" (`android:screenOrientation` and
  `setRequestedOrientation` work), **full screen** (tap with three fingers to
  show the bars) and **keep the screen on**.
- **Back Up Saves / Restore Saves**: everything an app saved (files,
  databases, SharedPreferences) as a .zip to keep in Files or move to
  another iPhone. App info also shows play time and the **last run log**,
  which you can share.
- **App bundles**: `.apks`, `.xapk` and `.apkm` install their main APK.
  OBB game data in an XAPK is copied to Shared Storage.
- **Download from a link**: Install or Downloads › + › Download from a link.
- **Shared Storage**: the virtual phone's `/sdcard` is the "Shared Storage"
  folder in Files › On My iPhone › APK Sandbox, so you can add game data.

Husk itself goes further: it runs native Android code and a whole LineageOS
virtual machine. Both need JIT, which iOS 12 doesn't give to apps, so those
parts can't come to APK Sandbox.

## What Android apps can do in the sandbox
- Layouts from `res/layout/*.xml` and views made in code: TextView, Button,
  EditText, CheckBox/Switch, ImageView, SeekBar, ProgressBar, LinearLayout and
  other containers, **ListView/GridView with ArrayAdapter or their own
  BaseAdapter** (item clicks, `notifyDataSetChanged`, empty view).
- Click listeners, `android:onClick`, Toast, AlertDialog, Log and
  `System.out` (in the log), Handler/postDelayed timers, several screens with
  `startActivity` and Intent extras, the Back key, Activity lifecycle
  (pause/stop/resume when you leave and come back).
- Each app's own **private storage**: SharedPreferences, and files in
  `getFilesDir()`/`getCacheDir()` via `java.io.File`, `FileOutputStream` and
  `FileInputStream`. Apps can't touch files outside their folders and the
  shared "sdcard".
- `Build`, `Runtime.maxMemory()`, `ActivityManager.getMemoryInfo()` /
  `getMemoryClass()` / `isLowRamDevice()` describe the 1 GB virtual phone.

## Memory (1 GB RAM)
- Each app gets a **Java heap limit** that depends on the iPhone: 160 MB on a
  1 GB iPhone, 320 MB on a 2 GB iPhone 7. An app that asks for more gets
  `java.lang.OutOfMemoryError` (which it can catch), instead of iOS killing
  APK Sandbox.
- Java arrays are stored compactly (a `byte[]` costs 1 byte per element).
- An installed app's code is unpacked once at install time and
  **memory-mapped** at launch, so iOS can page it out instead of counting it
  against the app.
- Big images are decoded at screen size, not full size.
- When iOS warns about memory, background apps are stopped first (like
  Android's low-memory killer) and the visible app frees its caches. It is only
  stopped if memory is still short. On 1 GB iPhones only one Android app runs
  at a time.

## Honest limits
This doesn't emulate Android, and nothing can run *every* APK on iOS. These
don't work:
- **Native code** (`lib/*.so`): games, Unity/Flutter/React Native apps, most
  emulators.
- OpenGL, SurfaceView game loops on their own thread, WebView,
  RecyclerView, Fragments, Jetpack Compose UIs, Spinner.
- Google Play services, networking, camera and sensors inside Android apps.

Small apps work best: a hello-world, a counter, a to-do list, a calculator or a
school project made with Android Studio's "Empty Views Activity" template.
Missing DEX files, invalid launcher classes and unsupported Android APIs show
explicit errors in the log.

## Install on your iPhone 7
The build is an unsigned `ApkSandbox.ipa` (and the same file as
`ApkSandbox.tipa`). Get it from the Codemagic build artifacts (see below).

- **iOS 15 (iPhone 7 on 15.0–15.8):** install **TrollStore**, then open
  `ApkSandbox.tipa` with it. TrollStore installs it permanently, with no
  re-signing and no 7-day limit.
- **iOS 12 (12.2 or newer):** use **Sideloadly** (Windows/Mac) or **AltStore**
  with your free Apple ID: drag in `ApkSandbox.ipa`, sign in and install.
  With a free account the app has to be re-signed every 7 days. iOS 12.0 and
  12.1 don't include the Swift runtime, so the app needs iOS 12.2 or newer (an
  iPhone 7 on 12.0/12.1 can only update to iOS 15 now, which is also fine).
- Sideloadly/AltStore also work on iOS 15 if you don't use TrollStore.

## Build the IPA (GitHub + Codemagic)
1. On https://codemagic.io, connect this repo. The **apk-sandbox-ios**
   workflow builds automatically for every push to `main` (the result shows
   as a check on the commit in GitHub).
2. Codemagic runs `xcodegen` to create `ApkSandbox.xcodeproj`, builds with
   Xcode 16.4 for iOS 12.0+ on arm64, and publishes `ApkSandbox.ipa` and
   `ApkSandbox.tipa`.

## Code layout
```
Sources/
  Apk/   ZipArchive, BinaryXML (AXML), ResourceTable (resources.arsc), DexFile,
         ApkPackage, PackageManager (install / update / uninstall / app data)
  VM/    VM.swift (Dalvik interpreter), VirtualDevice (1 GB phone, heap budget),
         Framework*.swift (Android/Java library: views, lists, files, memory…),
         AndroidRuntime.swift (activities, lifecycle, views, Java strings)
  UI/    Home (launcher), Installer, App info, Downloads, Settings,
         RunViewController (Android-style app screen), TaskManager (running apps),
         LayoutInflater (Android XML → UIKit)
Tools/
  LinuxRunner/  the real engine as a Linux command-line tool (run, tap, install)
  TestApps/     small Android apps (Java source + prebuilt APKs) used as tests
  UIKitCheck/   type-checks the iOS screens on Linux
  AppIcon/      draws the app icon
```

## Testing without an iPhone
```
bash Tools/LinuxRunner/build.sh            # needs Swift 5.10 for Linux
R=Tools/LinuxRunner/build/runner
$R Tools/TestApps/prebuilt/counter.apk tap:plus tap:open
$R Tools/TestApps/prebuilt/todo.apk tap:add "tap:Buy milk"
$R Tools/TestApps/prebuilt/memtest.apk "tap:Fill memory"
$R Tools/TestApps/prebuilt/tapgame.apk wait:500 touch:360,640
$R backup com.kungops.counter saves.zip && $R restore com.kungops.counter saves.zip
$R install Tools/TestApps/prebuilt/counter.apk && $R run com.kungops.counter
bash Tools/UIKitCheck/typecheck.sh
```
`.github/workflows/linux-runner.yml` runs all of these.
