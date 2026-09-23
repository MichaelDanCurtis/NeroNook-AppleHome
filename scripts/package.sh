#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if ! xcodebuild -project AppleHome.xcodeproj -scheme AppleHome -configuration Release \
    -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/SignedDerivedData \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="${NERONOOK_APPLE_TEAM:-2GFVXB3249}" build > build/signing.log 2>&1; then
    sed -n '/error:/p' build/signing.log
    exit 1
fi
app="$PWD/build/SignedDerivedData/Build/Products/Release-maccatalyst/Apple Home Module.app"
codesign --verify --deep --strict "$app"
python3 scripts/verify-provisioning.py "$app"
ditto "$app" "$PWD/build/Apple Home Module.app"
ditto -c -k --sequesterRsrc --keepParent "$PWD/build/Apple Home Module.app" "$PWD/build/NeroNook-AppleHome-0.2.1.zip"
