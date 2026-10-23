#!/usr/bin/env bash
# Install the signed APK on the phone and side-load bundled (locally
# converted) weights into the app's external files dir over adb.
# Works over USB debugging or Wireless debugging (`adb connect <ip>:<port>`).
#   ADB_SERIAL=R5CX... 60_install_to_phone.sh     (pick a device)
set -euo pipefail
source "$(dirname "$0")/env.sh"
APK="${APK:-$S25_HOME/out/MLCChat-s25-release.apk}"
BUNDLE="$MLC_LLM_SOURCE_DIR/android/MLCChat/dist/bundle"
PKG="ai.mlc.mlcchat"
APP_DIR="/sdcard/Android/data/$PKG/files"

ADB=(adb)
[ -n "${ADB_SERIAL:-}" ] && ADB=(adb -s "$ADB_SERIAL")
sh_dev() { "${ADB[@]}" shell "$@" | tr -d '\r'; }

[ "$("${ADB[@]}" get-state 2>/dev/null || true)" = "device" ] || {
  echo "ERROR: no adb device (enable USB or Wireless debugging, then 'adb devices')" >&2; exit 1; }
echo "device: $(sh_dev getprop ro.product.model), Android $(sh_dev getprop ro.build.version.release), SDK $(sh_dev getprop ro.build.version.sdk)"

# -r keeps app data (downloaded models) when upgrading with the same key.
"${ADB[@]}" install -r "$APK"

# The app creates its external files dir on first launch.
"${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 4
"${ADB[@]}" shell am force-stop "$PKG"

if [ -d "$BUNDLE" ]; then
  for dir in "$BUNDLE"/*/; do
    id="$(basename "$dir")"
    [ -f "$dir/tensor-cache.json" ] || continue
    n_local="$(ls "$dir" | grep -c '^params_shard_.*\.bin$' || true)"
    stage="$APP_DIR/.$id.partial"
    echo "== pushing $id ($n_local shards, $(du -sh "$dir" | cut -f1))"
    sh_dev rm -rf "$stage"
    sh_dev mkdir -p "$stage"
    "${ADB[@]}" push "$dir". "$stage/"
    n_remote="$(sh_dev "ls $stage" | grep -c '^params_shard_.*\.bin$' || true)"
    [ "$n_remote" = "$n_local" ] || { echo "ERROR: $id pushed $n_remote/$n_local shards" >&2; exit 1; }
    sh_dev rm -rf "$APP_DIR/$id"
    sh_dev mv "$stage" "$APP_DIR/$id"
  done
fi

"${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
echo "Installed. Crash triage: adb logcat -s TVM_RUNTIME AndroidRuntime MLCChat"
