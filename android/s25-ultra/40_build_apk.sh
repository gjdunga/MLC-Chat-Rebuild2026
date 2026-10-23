#!/usr/bin/env bash
# Build the signed release APK (R8-minified) and run Android lint as a gate.
#
# Signing: on first run a release keystore is generated under
# $S25_HOME/keystore with a random password stored next to it (mode 600).
# BACK IT UP. Android only installs an update over an existing app if it is
# signed with the same key; losing the key means uninstalling (and losing
# downloaded models) to install a newer build. This is not recoverable.
set -euo pipefail
source "$(dirname "$0")/env.sh"
APP_DIR="$MLC_LLM_SOURCE_DIR/android/MLCChat"
KS_DIR="$S25_HOME/keystore"
KS="$KS_DIR/mlcchat-release.jks"
KS_ENV="$KS_DIR/signing.env"

[ -f "$APP_DIR/dist/lib/mlc4j/output/arm64-v8a/libtvm4j_runtime_packed.so" ] || {
  echo "ERROR: run 30_compile_and_package.sh first" >&2; exit 1; }

if [ ! -f "$KS" ]; then
  umask 077
  mkdir -p "$KS_DIR"
  pass="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
  keytool -genkeypair -keystore "$KS" -storetype PKCS12 -alias mlcchat \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -storepass "$pass" -keypass "$pass" \
    -dname "CN=MLC Chat S25 local build"
  cat > "$KS_ENV" <<ENV
export MLC_KEYSTORE="$KS"
export MLC_KEYSTORE_PASSWORD="$pass"
export MLC_KEY_ALIAS="mlcchat"
export MLC_KEY_PASSWORD="$pass"
ENV
  chmod 600 "$KS" "$KS_ENV"
  echo "Created release keystore $KS (password in $KS_ENV). Back up both files."
fi
# shellcheck disable=SC1090
source "$KS_ENV"

cd "$APP_DIR"
# Dependency checksums are pinned in gradle/verification-metadata.xml and
# enforced (org.gradle.dependency.verification=strict). After changing a
# dependency, regenerate with:
#   ./gradlew --write-verification-metadata sha256 help
./gradlew --no-daemon :app:assembleRelease :app:lintRelease

apk="$APP_DIR/app/build/outputs/apk/release/app-release.apk"
[ -f "$apk" ] || { echo "ERROR: no signed APK at $apk" >&2; exit 1; }
mkdir -p "$S25_HOME/out"
cp "$apk" "$S25_HOME/out/MLCChat-s25-release.apk"
echo "APK: $S25_HOME/out/MLCChat-s25-release.apk"
echo "Lint report: $APP_DIR/app/build/reports/lint-results-release.html"
echo "Next: 50_verify_apk.sh"
