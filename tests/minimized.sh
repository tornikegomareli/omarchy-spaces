#!/usr/bin/env bash
# On a floating workspace, minimize and restore only a disposable test window.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
preview=$(mktemp -d)
original=$(hyprctl activewindow -j | jq -r '.address // empty')
cleanup() {
  rm -rf -- "$preview"
  if [[ -n $original ]]; then
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$original\" })" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
ln -s "$shell_dir/Commons" "$preview/Commons"
ln -s "$shell_dir/Ui" "$preview/Ui"
for name in Spaces.qml SpacesSettings.qml Model.js assets; do
  ln -s "$repo/$name" "$preview/$name"
done
cp "$repo/tests/minimized.test.qml" "$preview/shell.qml"
QT_QPA_PLATFORM=wayland timeout 20 qs -p "$preview"
