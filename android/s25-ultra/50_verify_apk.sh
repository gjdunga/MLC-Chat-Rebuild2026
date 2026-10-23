#!/usr/bin/env bash
# Verify the release APK against the S25 build's security and platform
# requirements. Exits non-zero on the first failed gate.
set -euo pipefail
source "$(dirname "$0")/env.sh"
APK="${1:-$S25_HOME/out/MLCChat-s25-release.apk}"
BT="$ANDROID_HOME/build-tools/${S25_BUILD_TOOLS#build-tools;}"
READELF="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[ -f "$APK" ] || fail "APK not found: $APK"

# 1. Signature: v2+ scheme, release key (not the debug key).
sig="$("$BT/apksigner" verify --verbose --print-certs "$APK")"
echo "$sig" | grep -q "Verified using v2 scheme (APK Signature Scheme v2): true" || fail "no v2 signature"
echo "$sig" | grep -q "CN=Android Debug" && fail "signed with the debug key"
pass "signed (v2+), cert: $(echo "$sig" | grep -m1 'certificate DN' | cut -d: -f2-)"

# 2. SDK levels.
badging="$("$BT/aapt2" dump badging "$APK")"
target="$(echo "$badging" | sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p")"
[ "$target" -ge 37 ] || fail "targetSdk $target < 37"
pass "targetSdk $target"

# 3. Permissions: exactly the allow-list.
perms="$("$BT/aapt2" dump permissions "$APK" | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" | sort)"
allowed=$'ai.mlc.mlcchat.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION\nandroid.permission.INTERNET'
extra="$(comm -23 <(echo "$perms") <(echo "$allowed" | sort))"
[ -z "$extra" ] || fail "unexpected permissions: $extra"
pass "permissions: $(echo "$perms" | tr '\n' ' ')"

# 4. Manifest flags.
xml="$("$BT/aapt2" dump xmltree --file AndroidManifest.xml "$APK")"
echo "$xml" | grep -q 'allowBackup.*=false' || fail "allowBackup not false"
echo "$xml" | grep -q 'usesCleartextTraffic.*=false' || fail "cleartext not disabled"
echo "$xml" | grep -q 'networkSecurityConfig' || fail "no network security config"
echo "$xml" | grep -q 'debuggable.*=true' && fail "debuggable release build"
pass "allowBackup=false, cleartext off, networkSecurityConfig set, not debuggable"

# 5. 16 KB page-size compatibility: every arm64 .so has LOAD segments aligned
#    to >= 16 KB, and is stored uncompressed + 16 KB-aligned in the zip.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
unzip -q -o "$APK" 'lib/arm64-v8a/*' -d "$tmp"
for so in "$tmp"/lib/arm64-v8a/*.so; do
  for a in $("$READELF" -lW "$so" | awk '/LOAD/ {print $NF}'); do
    (( 16#${a#0x} >= 16384 )) || fail "$(basename "$so") LOAD alignment $a < 16 KB"
  done
done
"$BT/zipalign" -c -P 16 -v 4 "$APK" >/dev/null || fail "zip not 16 KB page-aligned"
pass "16 KB ELF alignment + zipalign -P 16 ($(ls "$tmp"/lib/arm64-v8a | tr '\n' ' '))"

# 6. R8 kept the JNI surface the native runtime calls into.
unzip -q -o "$APK" 'classes*.dex' -d "$tmp"
grep -qa "Lorg/apache/tvm/Function;" "$tmp"/classes*.dex || fail "org.apache.tvm.Function stripped by R8"
for cls in AppConfig ModelRecord ModelConfig ParamsConfig; do
  grep -qa "Lai/mlc/mlcchat/$cls;" "$tmp"/classes*.dex || fail "Gson model ai.mlc.mlcchat.$cls renamed/stripped by R8"
done
pass "JNI classes and Gson config models present after R8"

echo "All gates passed for $APK"
