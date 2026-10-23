#!/usr/bin/env bash
# Convert every "source": "convert" model in s25-models.json from its original
# Hugging Face checkpoint into MLC weights under $S25_HOME/weights/<model_id>.
# Uses the compiler built from source by 10_build_compiler.sh.
#
# Downloads use the Hugging Face CLI over HTTPS; weights are safetensors
# (no pickle code execution). Disk: ~2.5x the bf16 checkpoint size.
set -euo pipefail
source "$(dirname "$0")/env.sh"
PY="$S25_VENV/bin/python"
MODELS_JSON="${MODELS_JSON:-$_S25_DIR/s25-models.json}"

mapfile -t ROWS < <("$PY" -I - "$MODELS_JSON" <<'PYEOF'
import json, sys
for m in json.load(open(sys.argv[1]))["models"]:
    if m.get("source") == "convert":
        o = m.get("overrides", {})
        print("\t".join([m["model_id"], m["hf_repo"], m["quantization"], m["conv_template"],
                         str(o.get("context_window_size", 4096)), str(o.get("prefill_chunk_size", 256))]))
PYEOF
)

for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r model_id repo quant conv ctx prefill <<< "$row"
  out="$S25_HOME/weights/$model_id"
  if [ -f "$out/tensor-cache.json" ] && [ -f "$out/mlc-chat-config.json" ]; then
    echo "== $model_id already converted, skipping (delete $out to redo)"
    continue
  fi
  src="$S25_HOME/hf/$repo"
  echo "== $model_id <- $repo ($quant)"
  "$S25_VENV/bin/hf" download "$repo" --local-dir "$src" \
    --include "*.json" --include "*.safetensors" --include "*.txt" --include "tokenizer*"
  rm -rf "$out.partial"
  "$PY" -m mlc_llm convert_weight "$src" --quantization "$quant" --device cpu -o "$out.partial"
  "$PY" -m mlc_llm gen_config "$src" --quantization "$quant" --conv-template "$conv" \
    --context-window-size "$ctx" --prefill-chunk-size "$prefill" -o "$out.partial"
  rm -rf "$out"
  mv "$out.partial" "$out"
  du -sh "$out"
done
echo "Weights ready under $S25_HOME/weights"
