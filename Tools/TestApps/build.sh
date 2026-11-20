#!/bin/bash
# Builds the small test APKs in this folder from Java source, without the
# Android SDK. Needs: a JDK (javac, jar), python3, apktool.jar and dex2jar.
#
#   APKTOOL=/path/apktool.jar DEX2JAR=/path/dex-tools-v2.4 ./build.sh
#
# Output: prebuilt/<app>.apk (already committed, so you only need this
# script when you change a test app).
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
APKTOOL="${APKTOOL:?set APKTOOL to apktool.jar}"
DEX2JAR="${DEX2JAR:?set DEX2JAR to the dex-tools folder}"
OUT="$H/prebuilt"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT" "$WORK/stubs"

# 1. Android API stubs (compile-time only, never packaged).
javac --release 8 -nowarn -d "$WORK/stubs" $(find "$H/android-stubs" -name '*.java')

build_app() {
    local app="$1"
    local src="$H/$app"
    local w="$WORK/$app"
    mkdir -p "$w/proj" "$w/classes"
    cp "$src/AndroidManifest.xml" "$w/proj/"
    cp -R "$src/res" "$w/proj/res"
    if [ -f "$src/icon.txt" ]; then
        mkdir -p "$w/proj/res/drawable"
        python3 "$H/make_icon.py" "$(cat "$src/icon.txt")" "$w/proj/res/drawable/ic_launcher.png"
    fi
    local vcode vname
    vcode="$(python3 -c "import re,sys; print(re.search(r'versionCode=\"([^\"]+)\"', open(sys.argv[1]).read()).group(1))" "$src/AndroidManifest.xml")"
    vname="$(python3 -c "import re,sys; print(re.search(r'versionName=\"([^\"]+)\"', open(sys.argv[1]).read()).group(1))" "$src/AndroidManifest.xml")"
    cat > "$w/proj/apktool.yml" <<EOF
version: 2.10.0
apkFileName: $app.apk
isFrameworkApk: false
usesFramework:
  ids:
  - 1
sdkInfo:
  minSdkVersion: 16
  targetSdkVersion: 28
packageInfo:
  forcedPackageId: 127
versionInfo:
  versionCode: $vcode
  versionName: $vname
doNotCompress:
- resources.arsc
EOF
    # 2. Resources + binary manifest.
    java -jar "$APKTOOL" b -q "$w/proj" -o "$w/res.apk"
    # 3. Read back the resource ids aapt2 picked and write R.java.
    java -jar "$APKTOOL" d -q -s -f "$w/res.apk" -o "$w/decoded"
    local pkg
    pkg="$(python3 -c "import re,sys; print(re.search(r'package=\"([^\"]+)\"', open(sys.argv[1]).read()).group(1))" "$src/AndroidManifest.xml")"
    mkdir -p "$w/gen"
    python3 "$H/make_r.py" "$pkg" "$w/decoded/res/values/public.xml" > "$w/gen/R.java"
    # 4. Java -> .class -> classes.dex
    javac --release 8 -nowarn -cp "$WORK/stubs" -d "$w/classes" "$w/gen/R.java" $(find "$src/src" -name '*.java')
    (cd "$w/classes" && jar cf "$w/app.jar" .)
    bash "$DEX2JAR/d2j-jar2dex.sh" -f -o "$w/classes.dex" "$w/app.jar" >/dev/null
    # 5. Put classes.dex into the APK.
    cp "$w/res.apk" "$OUT/$app.apk"
    (cd "$w" && zip -q "$OUT/$app.apk" classes.dex)
    echo "built $OUT/$app.apk"
}

for app in counter memtest todo; do build_app "$app"; done
