#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# MLX requires xcodebuild to compile Metal shaders
# swift build doesn't compile .metal files

# Build using xcodebuild (compiles Metal shaders)
if [ ! -f "Secrets.xcconfig" ]; then
    echo "Warning: Secrets.xcconfig not found. Google OAuth will not work."
    echo "Copy Secrets.xcconfig.example to Secrets.xcconfig and fill in the values."
fi

echo "Building with xcodebuild..."
mkdir -p .build
BUILD_LOG=".build/xcodebuild.log"

if ! xcodebuild \
    -scheme Gophy \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    build >"$BUILD_LOG" 2>&1; then
    grep -E "(error:|warning:|\*\* BUILD)" "$BUILD_LOG" | tail -40 || tail -40 "$BUILD_LOG"
    echo "xcodebuild failed; full log: $BUILD_LOG" >&2
    exit 1
fi

grep -E "(error:|warning:|\*\* BUILD)" "$BUILD_LOG" | tail -20 || true

echo "Build completed, creating app bundle..."

# Create app bundle structure
APP_DIR=".build/debug/Gophy.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

# Copy main executable
cp .build/xcode/Build/Products/Debug/Gophy "$APP_DIR/Contents/MacOS/"

# Copy Info.plist and substitute secrets from xcconfig
cp Sources/Gophy/Info.plist "$APP_DIR/Contents/"
if [ -f "Secrets.xcconfig" ]; then
    _client_id=$(grep '^GOOGLE_CLIENT_ID' Secrets.xcconfig | head -1 | cut -d'=' -f2- | xargs)
    _client_secret=$(grep '^GOOGLE_CLIENT_SECRET' Secrets.xcconfig | head -1 | cut -d'=' -f2- | xargs)
    if [ -n "$_client_id" ]; then
        plutil -replace GoogleClientID -string "$_client_id" "$APP_DIR/Contents/Info.plist"
    fi
    if [ -n "$_client_secret" ]; then
        plutil -replace GoogleClientSecret -string "$_client_secret" "$APP_DIR/Contents/Info.plist"
    fi
fi

# Copy app icon
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
fi

# Copy MLX Metal library bundle (CRITICAL for Metal shader support)
if [ -d ".build/xcode/Build/Products/Debug/mlx-swift_Cmlx.bundle" ]; then
    cp -R ".build/xcode/Build/Products/Debug/mlx-swift_Cmlx.bundle" "$APP_DIR/Contents/Resources/"
    echo "Copied MLX Metal library bundle"
fi

# Sign the app with a stable identity so macOS remembers permissions (mic, keychain) across rebuilds.
# Uses "Gophy Development" self-signed cert if available, falls back to ad-hoc signing.
SIGN_IDENTITY="Gophy Dev Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements Sources/Gophy/Gophy-debug.entitlements "$APP_DIR"
    echo "Signed with '$SIGN_IDENTITY' certificate (permissions persist across rebuilds)"
else
    codesign --force --deep --sign - --entitlements Sources/Gophy/Gophy-debug.entitlements "$APP_DIR"
    echo "Signed ad-hoc (permissions may reset on rebuild)"
fi

echo "Build complete: $APP_DIR"
