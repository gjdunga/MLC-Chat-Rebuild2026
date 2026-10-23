#!/usr/bin/env bash
# Build the MLC compiler toolchain (TVM + mlc_llm) from this repository's
# source into $S25_VENV. Model libraries compiled with it match the TVM
# runtime that 40_build_apk.sh packs into the APK, because both come from the
# 3rdparty/tvm submodule commit checked out here.
#
# Time: ~40-70 min on a 4-8 core laptop (TVM with static LLVM dominates).
# Disk: ~6 GB under $S25_HOME and the build dirs.
set -euo pipefail
source "$(dirname "$0")/env.sh"

JOBS="${JOBS:-$(nproc)}"
command -v "$S25_PYTHON" >/dev/null || { echo "ERROR: $S25_PYTHON not found (run 00_bootstrap_ubuntu.sh)" >&2; exit 1; }
command -v llvm-config >/dev/null || { echo "ERROR: llvm-config not found (run 00_bootstrap_ubuntu.sh)" >&2; exit 1; }

git -C "$MLC_LLM_SOURCE_DIR" submodule update --init --recursive

mkdir -p "$S25_HOME"
[ -x "$S25_VENV/bin/python" ] || "$S25_PYTHON" -m venv "$S25_VENV"
PY="$S25_VENV/bin/python"
"$PY" -m pip install -q --upgrade pip
"$PY" -m pip install -q "scikit-build-core>=0.11" "setuptools-scm>=8" cmake ninja

# 1. TVM FFI (pinned by the TVM submodule), then TVM itself with LLVM linked
#    statically so the venv does not depend on the system LLVM at run time.
"$PY" -m pip install -q "$TVM_SOURCE_DIR/3rdparty/tvm-ffi"

TVM_BUILD="$TVM_SOURCE_DIR/build"
mkdir -p "$TVM_BUILD"
cp "$TVM_SOURCE_DIR/cmake/config.cmake" "$TVM_BUILD/config.cmake"
cat >> "$TVM_BUILD/config.cmake" <<'CFG'
set(CMAKE_BUILD_TYPE Release)
set(USE_LLVM "llvm-config --ignore-libllvm --link-static")
set(HIDE_PRIVATE_SYMBOLS ON)
set(USE_CUDA OFF)
set(USE_METAL OFF)
set(USE_VULKAN OFF)
set(USE_OPENCL OFF)
CFG
cmake -S "$TVM_SOURCE_DIR" -B "$TVM_BUILD" -G Ninja
cmake --build "$TVM_BUILD" --parallel "$JOBS"
export TVM_LIBRARY_PATH="$TVM_BUILD"
"$PY" -m pip install -q -e "$TVM_SOURCE_DIR" --no-build-isolation --config-settings=build-dir="$TVM_BUILD"

# 2. mlc_llm C++ module + Python package. Only the deps that compile,
#    convert_weight and package import; the declared CUDA/flashinfer stack is
#    several GB and unused for an Android target.
MLC_BUILD="$MLC_LLM_SOURCE_DIR/build"
mkdir -p "$MLC_BUILD"
cat > "$MLC_BUILD/config.cmake" <<CFG
set(TVM_SOURCE_DIR $TVM_SOURCE_DIR)
set(CMAKE_BUILD_TYPE Release)
set(USE_CUDA OFF)
set(USE_CUTLASS OFF)
set(USE_CUBLAS OFF)
set(USE_ROCM OFF)
set(USE_VULKAN OFF)
set(USE_METAL OFF)
set(USE_OPENCL OFF)
set(USE_OPENCL_ENABLE_HOST_PTR OFF)
set(USE_THRUST OFF)
CFG
cmake -S "$MLC_LLM_SOURCE_DIR" -B "$MLC_BUILD" -G Ninja
cmake --build "$MLC_BUILD" --parallel "$JOBS"
"$PY" -m pip install -q --no-deps -e "$MLC_LLM_SOURCE_DIR/python"
"$PY" -m pip install -q numpy ml_dtypes safetensors tqdm psutil shortuuid requests \
  fastapi uvicorn pydantic tiktoken sentencepiece prompt_toolkit openai huggingface_hub
"$PY" -m pip install -q torch --index-url https://download.pytorch.org/whl/cpu

# 3. Smoke test: both libraries load and report the same TVM commit.
"$PY" - <<'PYCHK'
import tvm, mlc_llm
info = tvm.support.libinfo()
print("TVM", tvm.__version__, "commit", info.get("GIT_COMMIT_HASH"), "LLVM", info.get("LLVM_VERSION"))
print("mlc_llm", mlc_llm.__file__)
PYCHK
echo "Compiler ready in $S25_VENV"
