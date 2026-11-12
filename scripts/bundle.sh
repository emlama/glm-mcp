#!/bin/zsh
# Builds "build/GLM MCP.app" (release, ad-hoc signed).
#   --install    also copy it to ~/Applications (quitting a running copy first)
#   --universal  build for arm64 and x86_64 (requires Xcode)
set -euo pipefail
cd "${0:A:h}/.."
install=0; archs=()
for arg in "$@"; do
  case $arg in
    --install) install=1 ;;
    --universal) archs=(--arch arm64 --arch x86_64) ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
scripts/swiftw build -c release --product GLMApp $archs
BIN=$(scripts/swiftw build -c release --product GLMApp $archs --show-bin-path)/GLMApp
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
