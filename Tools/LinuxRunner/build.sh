#!/bin/bash
# Builds a Linux command-line runner from the app's real engine sources
# (Sources/Apk, Sources/VM, ViewBox, LayoutInflater, ActivityHost), using
# small stand-ins for UIKit and Compression. Lets you run an APK and tap
# buttons without an iPhone:
#   ./build.sh && build/runner app.apk tap:7 tap:id_name wait:1000
# Needs a Linux Swift 5.10 toolchain on PATH (swiftc) and zlib.
set -e
H="$(cd "$(dirname "$0")" && pwd)"
SRC="$H/../../Sources"
mkdir -p "$H/build" && cd "$H/build"
rm -f libUIKit.a libCompression.a
swiftc -emit-module -emit-library -static -module-name UIKit -parse-as-library -O "$H/UIKit/UIKit.swift" -o libUIKit.a -emit-module-path UIKit.swiftmodule
swiftc -emit-module -emit-library -static -module-name Compression -parse-as-library -O -I "$H/CZlib" "$H/Compression/Compression.swift" -o libCompression.a -emit-module-path Compression.swiftmodule
FILES="$(ls "$SRC"/Apk/*.swift "$SRC"/VM/*.swift) $SRC/UI/ViewBox.swift $SRC/UI/LayoutInflater.swift $SRC/UI/ActivityHost.swift $SRC/UI/CanvasView.swift $SRC/BuildInfo.swift"
# APKSANDBOX_RUNNER leaves out the iOS-only drawing code (CoreGraphics).
swiftc -O -D APKSANDBOX_RUNNER -I . -I "$H/CZlib" -L . -lUIKit -lCompression -lz $FILES "$H/Runner/main.swift" "$H/Runner/Shims.swift" -o runner
echo "BUILD OK: $H/build/runner"
