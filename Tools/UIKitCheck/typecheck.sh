#!/bin/bash
# Type-checks every Swift file of the iOS app on Linux against a
# declarations-only UIKit (UIKit.swift here), so mistakes in the screens are
# caught without a Mac. Codemagic still does the real iOS build.
#   Tools/UIKitCheck/typecheck.sh      (needs swiftc 5.10 and libsqlite3-dev)
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SRC="$H/../../Sources"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/mod" "$W/src"
swiftc -emit-module -parse-as-library -module-name UIKit "$H/UIKit.swift" -emit-module-path "$W/mod/UIKit.swiftmodule"
swiftc -emit-module -parse-as-library -module-name Compression -I "$H/../LinuxRunner/CZlib" \
    "$H/../LinuxRunner/Compression/Compression.swift" -emit-module-path "$W/mod/Compression.swiftmodule"
# PC Link uses AVFoundation / camera APIs that have no stand-in here.
for f in $(find "$SRC" -name '*.swift' ! -name 'PCLinkViewController.swift'); do
    # Objective-C bits don't exist on Linux: drop @objc, turn #selector into a call.
    sed -e 's/@objc //g' -e 's/#selector(/__selector(/g' -e 's/@UIApplicationMain//' "$f" > "$W/src/$(basename "$f")"
done
cat > "$W/src/_Shims.swift" <<'SHIM'
import UIKit
func autoreleasepool<T>(invoking body: () throws -> T) rethrows -> T { return try body() }
final class PCLinkViewController: UIViewController {}
SHIM
swiftc -typecheck -continue-building-after-errors -parse-as-library -I "$W/mod" -I "$H/../LinuxRunner/CZlib" -I "$H/../LinuxRunner/CSQLite" "$W"/src/*.swift
echo "TYPECHECK OK"
