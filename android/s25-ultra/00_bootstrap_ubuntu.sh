#!/usr/bin/env bash
# One-time setup of a Linux x86_64 laptop (Ubuntu 24.04, native or WSL2) for
# building MLC Chat for the Galaxy S25 Ultra. Idempotent; safe to rerun.
#
# Installs: build toolchain + LLVM 18 dev (apt), Rust aarch64-linux-android
# target (rustup), Android cmdline-tools/SDK/NDK (into $S25_HOME, no sudo).
# Every Android download is checked: cmdline-tools by the SHA-256 pinned in
# env.sh; SDK packages by sdkmanager against Google's signed repository.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if [ "$(uname -m)" != "x86_64" ]; then
  echo "ERROR: x86_64 host required (Android NDK + TVM LLVM build)." >&2
  exit 1
fi

# 1. System packages (sudo only when not already root, e.g. inside Docker).
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"
if command -v apt-get >/dev/null; then
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -q
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    build-essential git git-lfs cmake ninja-build curl unzip zip pkg-config \
    python3.12 python3.12-venv python3.12-dev \
    llvm-18-dev libpolly-18-dev clang-18 libzstd-dev zlib1g-dev libxml2-dev libedit-dev \
    openjdk-21-jdk-headless ca-certificates
  # Ubuntu ships llvm-config versioned; TVM's CMake calls plain llvm-config.
  command -v llvm-config >/dev/null || $SUDO ln -sf /usr/bin/llvm-config-18 /usr/local/bin/llvm-config
else
  echo "WARN: not a Debian/Ubuntu host; install the equivalents of the apt list above manually." >&2
fi

# 2. Rust (tokenizers-cpp builds a Rust static lib for the phone).
if ! command -v rustup >/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  source "$HOME/.cargo/env"
fi
rustup target add aarch64-linux-android

# 3. Android command-line tools, verified before unpacking.
mkdir -p "$ANDROID_HOME/cmdline-tools"
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/clt.zip" "https://dl.google.com/android/repository/$S25_CMDLINE_TOOLS_ZIP"
  echo "$S25_CMDLINE_TOOLS_SHA256  $tmp/clt.zip" | sha256sum -c -
  unzip -q "$tmp/clt.zip" -d "$tmp"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$tmp"
fi

# 4. SDK packages. Accepting licenses is required by sdkmanager; review them
#    with `sdkmanager --licenses` if you have not before.
yes | sdkmanager --licenses >/dev/null || true
sdkmanager --install "platform-tools" "$S25_PLATFORM" "$S25_BUILD_TOOLS" "ndk;$S25_NDK_VERSION"

echo
echo "Bootstrap done."
echo "  ANDROID_HOME=$ANDROID_HOME"
echo "  ANDROID_NDK=$ANDROID_NDK"
echo "Next: 10_build_compiler.sh"
