#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PKGROOT="$BUILD_DIR/pkgroot"
OUT_DIR="$ROOT_DIR/dist"
VERSION="${VERSION:-0.1.0}"
PACKAGE_ID="com.company.qrreader"

echo "[1/6] Clean"
rm -rf "$BUILD_DIR" "$OUT_DIR"
mkdir -p "$PKGROOT/usr/local/libexec/$PACKAGE_ID"
mkdir -p "$PKGROOT/Library/LaunchAgents"
mkdir -p "$OUT_DIR"

echo "[2/6] Build daemon"
cd "$ROOT_DIR"
swift build -c release

echo "[3/6] Stage files"
cp ".build/release/qr-reader-daemon" "$PKGROOT/usr/local/libexec/$PACKAGE_ID/qr-reader-daemon"
chmod 755 "$PKGROOT/usr/local/libexec/$PACKAGE_ID/qr-reader-daemon"

cp "$ROOT_DIR/Resources/com.company.qrreader.plist" "$PKGROOT/Library/LaunchAgents/com.company.qrreader.plist"
chmod 644 "$PKGROOT/Library/LaunchAgents/com.company.qrreader.plist"

chmod +x "$ROOT_DIR/Scripts/preinstall" "$ROOT_DIR/Scripts/postinstall"

echo "[4/6] Build component pkg"
pkgbuild \
  --identifier "$PACKAGE_ID" \
  --version "$VERSION" \
  --root "$PKGROOT" \
  --scripts "$ROOT_DIR/Scripts" \
  "$BUILD_DIR/qr-reader-component.pkg"

echo "[5/6] Build product pkg (with installer wizard)"
# Inject version into distribution.xml
sed "s/version=\"0.1.0\"/version=\"$VERSION\"/" \
    "$ROOT_DIR/Resources/distribution.xml" > "$BUILD_DIR/distribution.xml"

productbuild \
  --distribution "$BUILD_DIR/distribution.xml" \
  --resources "$ROOT_DIR/Resources" \
  --package-path "$BUILD_DIR" \
  "$OUT_DIR/qr-reader-$VERSION.pkg"

echo "[6/6] Done"
echo "Output: $OUT_DIR/qr-reader-$VERSION.pkg"
