#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${1:-release}
APP_DIR="$PROJECT_DIR/dist/EchoSub.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
swift build --disable-sandbox -c "$CONFIGURATION"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/arm64-apple-macosx/$CONFIGURATION/EchoSub" "$CONTENTS_DIR/MacOS/EchoSub"
cp "$PROJECT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Support/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
chmod 755 "$CONTENTS_DIR/MacOS/EchoSub"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
