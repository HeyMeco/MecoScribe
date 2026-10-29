#!/bin/bash
# Builds MecoScribe.app (release) into ./dist.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/MecoScribeCLI/ScribeCommand.swift)"
APP="dist/MecoScribe.app"

swift build -c release --product MecoScribeApp
BIN="$(swift build -c release --product MecoScribeApp --show-bin-path)/MecoScribeApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MecoScribe"
cp Sources/MecoScribeApp/Resources/MecoScribe.icns "$APP/Contents/Resources/MecoScribe.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MecoScribe</string>
    <key>CFBundleDisplayName</key><string>MecoScribe</string>
    <key>CFBundleIdentifier</key><string>com.heymeco.MecoScribe</string>
    <key>CFBundleExecutable</key><string>MecoScribe</string>
    <key>CFBundleIconFile</key><string>MecoScribe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.heymeco.mecoscribe.project</string>
            <key>UTTypeDescription</key><string>MecoScribe Project</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string><string>public.zip-archive</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key><array><string>mscribe</string></array>
            </dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>MecoScribe Project</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key>
            <array><string>com.heymeco.mecoscribe.project</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Audio</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.audio</string><string>public.movie</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>MecoScribe Transcript</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array><string>public.plain-text</string><string>public.html</string><string>public.json</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
