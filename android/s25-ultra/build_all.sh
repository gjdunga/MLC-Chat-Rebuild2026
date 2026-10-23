#!/usr/bin/env bash
# Full pipeline on a laptop: compiler -> weights -> model libs + runtime -> APK -> gates.
# Each step is idempotent; rerun after a failure to resume.
# Install to the phone separately with 60_install_to_phone.sh (needs adb on the host).
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
"$D/10_build_compiler.sh"
"$D/20_convert_weights.sh"
"$D/30_compile_and_package.sh"
"$D/40_build_apk.sh"
"$D/50_verify_apk.sh"
