#!/usr/bin/env bash
# 1. Compile one model library per entry in s25-models.json for android:adreno
#    (Adreno 830 OpenCL; `mlc_llm package` alone would only use the generic
#    Android target).
# 2. Generate android/MLCChat/mlc-package-config.json from those libraries.
# 3. Run `mlc_llm package`: links the libraries into libmodel_android.a and
#    cross-compiles the TVM/MLC runtime + tokenizers with the NDK into
#    android/MLCChat/dist/lib/mlc4j (libtvm4j_runtime_packed.so).
set -euo pipefail
source "$(dirname "$0")/env.sh"
PY="$S25_VENV/bin/python"
MODELS_JSON="${MODELS_JSON:-$_S25_DIR/s25-models.json}"
APP_DIR="$MLC_LLM_SOURCE_DIR/android/MLCChat"
LIB_DIR="$S25_HOME/libs"
CFG_DIR="$S25_HOME/configs"
mkdir -p "$LIB_DIR" "$CFG_DIR"

[ -d "$ANDROID_NDK" ] || { echo "ERROR: NDK missing at $ANDROID_NDK (run 00_bootstrap_ubuntu.sh)" >&2; exit 1; }
rustup target list --installed | grep -q aarch64-linux-android || {
  echo "ERROR: rust target aarch64-linux-android missing (run 00_bootstrap_ubuntu.sh)" >&2; exit 1; }

# Fields are '|'-separated: with a tab, bash collapses empty fields.
mapfile -t ROWS < <("$PY" -I - "$MODELS_JSON" <<'PYEOF'
import json, sys
for m in json.load(open(sys.argv[1]))["models"]:
    o = m.get("overrides", {})
    ov = ";".join(f"{k}={v}" for k, v in o.items())
    print("|".join([m["model_id"], m["source"], m.get("model", ""), m["model_lib"], ov]))
PYEOF
)

for row in "${ROWS[@]}"; do
  IFS='|' read -r model_id source model model_lib overrides <<< "$row"
  if [ "$source" = "hf" ]; then
    # Compiling needs only the chat config; the app downloads weights later.
    cfg="$CFG_DIR/$model_id"
    mkdir -p "$cfg"
    repo="${model#HF://}"
    curl -fsSL --proto '=https' -o "$cfg/mlc-chat-config.json.new" \
      "https://huggingface.co/$repo/resolve/main/mlc-chat-config.json"
    # Replace only on change, so an unchanged model is not recompiled.
    if cmp -s "$cfg/mlc-chat-config.json.new" "$cfg/mlc-chat-config.json"; then
      rm "$cfg/mlc-chat-config.json.new"
    else
      mv "$cfg/mlc-chat-config.json.new" "$cfg/mlc-chat-config.json"
    fi
  else
    cfg="$S25_HOME/weights/$model_id"
    [ -f "$cfg/mlc-chat-config.json" ] || { echo "ERROR: $cfg not converted (run 20_convert_weights.sh)" >&2; exit 1; }
  fi
  lib="$LIB_DIR/$model_lib.tar"
  if [ -f "$lib" ] && [ "$lib" -nt "$cfg/mlc-chat-config.json" ]; then
    echo "== $model_lib up to date"
    continue
  fi
  echo "== compiling $model_lib for $S25_MLC_DEVICE"
  "$PY" -m mlc_llm compile "$cfg/mlc-chat-config.json" \
    --device "$S25_MLC_DEVICE" \
    --system-lib-prefix "${model_lib}_" \
    --overrides "$overrides" \
    -o "$lib.partial.tar"
  mv "$lib.partial.tar" "$lib"
done

# Package config consumed by `mlc_llm package` (absolute paths are local to
# this machine, so the file is generated, not committed).
"$PY" -I - "$MODELS_JSON" "$APP_DIR/mlc-package-config.s25.json" "$LIB_DIR" "$S25_HOME/weights" <<'PYEOF'
import json, sys
spec, out, lib_dir, weights = sys.argv[1:]
models = json.load(open(spec))["models"]
cfg = {"device": "android", "model_list": [], "model_lib_path_for_prepare_libs": {}}
for m in models:
    entry = {
        "model_id": m["model_id"],
        "model_lib": m["model_lib"],
        "estimated_vram_bytes": m["estimated_vram_bytes"],
        "overrides": m.get("overrides", {}),
    }
    if m["source"] == "hf":
        entry["model"] = m["model"]
    else:
        entry["model"] = f"{weights}/{m['model_id']}"
        entry["bundle_weight"] = True
    cfg["model_list"].append(entry)
    cfg["model_lib_path_for_prepare_libs"][m["model_lib"]] = f"{lib_dir}/{m['model_lib']}.tar"
json.dump(cfg, open(out, "w"), indent=2)
print("wrote", out)
PYEOF

cd "$APP_DIR"
"$PY" -m mlc_llm package --package-config mlc-package-config.s25.json --output dist

# `mlc_llm package` writes the laptop's absolute weights path as model_url for
# bundled models, which would ship your local paths inside the APK. Replace it
# with an unresolvable HTTPS URL (.invalid is reserved, RFC 2606): bundled
# weights are side-loaded by 60_install_to_phone.sh, and if a file is missing
# the app reports a failed download instead of fetching anything.
"$PY" -I - "$APP_DIR/dist/lib/mlc4j/src/main/assets/mlc-app-config.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p))
for m in cfg["model_list"]:
    if not m.get("model_url", "").startswith("https://"):
        m["model_url"] = f"https://bundled.invalid/{m['model_id']}"
json.dump(cfg, open(p, "w"), indent=2)
PYEOF

so="$APP_DIR/dist/lib/mlc4j/output/arm64-v8a/libtvm4j_runtime_packed.so"
[ -f "$so" ] || { echo "ERROR: runtime not built: $so" >&2; exit 1; }
ls -la "$so"
echo "Packaged. Next: 40_build_apk.sh"
