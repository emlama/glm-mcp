#!/bin/zsh
# Builds "build/GLM MCP.app" (release, ad-hoc signed).
#   --install    also copy it to ~/Applications (quitting a running copy first)
#   --universal  build for arm64 and x86_64
set -euo pipefail
cd "${0:A:h}/.."
install=0; universal=0
for arg in "$@"; do
  case $arg in
    --install) install=1 ;;
    --universal) universal=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
if (( universal )); then
  # One build per architecture with the native build system, then lipo. (`--arch a --arch b`
  # switches to Xcode's build system, which rejects some dependencies' manifests.)
  bins=()
  for triple in arm64-apple-macosx14.0 x86_64-apple-macosx14.0; do
    scripts/swiftw build -c release --product GLMApp --triple $triple
    bins+=("$(scripts/swiftw build -c release --product GLMApp --triple $triple --show-bin-path)/GLMApp")
  done
  mkdir -p build
  BIN=build/GLMApp-universal
  lipo -create -output $BIN $bins
else
  scripts/swiftw build -c release --product GLMApp
  BIN=$(scripts/swiftw build -c release --product GLMApp --show-bin-path)/GLMApp
fi
APP="build/GLM MCP.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GLMApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"
echo "Built $APP"
if (( install )); then
  osascript -e 'quit app "GLM MCP"' 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/"GLM MCP.app"
  cp -R "$APP" ~/Applications/
  echo "Installed ~/Applications/GLM MCP.app"
fi
