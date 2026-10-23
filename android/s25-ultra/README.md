# MLC Chat for the Galaxy S25 Ultra: build from source on a laptop

Builds a signed, hardened MLC Chat APK for the Galaxy S25 Ultra
(SM-S938U, Snapdragon 8 Elite for Galaxy, Adreno 830, 12 GB, Android 17 /
One UI 9) entirely from this repository's source: TVM compiler, MLC
runtime, tokenizers, model libraries and the Android app.

## Layers (what is built where)

| Layer | Built from | Runs on |
|---|---|---|
| Compiler (TVM + `mlc_llm` Python) | `3rdparty/tvm` + `python/` in this repo, LLVM 18 static | laptop |
| Model libraries (GPU kernels) | `mlc_llm compile --device android:adreno` | phone GPU (OpenCL) |
| Runtime (`libtvm4j_runtime_packed.so`) | same TVM commit, NDK r30, Rust tokenizers | phone CPU |
| App (`MLCChat`) | `android/MLCChat`, AGP 9.4.1, Kotlin 2.4.21 | phone |
| Weights | Hugging Face, downloaded by the app or converted locally | phone storage |

Why the compiler is built from source instead of the nightly wheels: as of
Oct 2026, `mlc-llm-nightly-cpu 0.26.dev6` calls `tvm.tirx.is_buffer_var`,
which `mlc-ai-nightly-cpu 0.26.dev246` does not have, so `mlc_llm compile`
fails. Building both from the same commit also guarantees the model
libraries match the runtime packed into the APK.

## Requirements

* x86_64 laptop with Ubuntu 24.04 (native or WSL2), or any OS with Docker.
* ~60 GB free disk, 16 GB RAM recommended (8 GB works with `JOBS=2`).
* Time on a 4-core laptop: compiler ~2 h (once), each model library ~10 min,
  runtime ~15 min, APK ~5 min.

## Build

Native Ubuntu / WSL2:

```
git clone --recursive <this fork> mlc-llm && cd mlc-llm
android/s25-ultra/00_bootstrap_ubuntu.sh   # apt, rustup target, SDK/NDK (checksummed)
android/s25-ultra/build_all.sh             # 10 -> 20 -> 30 -> 40 -> 50
android/s25-ultra/60_install_to_phone.sh   # USB or Wireless debugging
```

Docker (macOS x86_64, Windows, other Linux):

```
docker build -t mlc-s25 android/s25-ultra
docker run --rm -it -v "$PWD":/work -v mlc-s25-home:/root/.mlc-s25 -w /work \
  mlc-s25 android/s25-ultra/build_all.sh
android/s25-ultra/60_install_to_phone.sh   # on the host, needs adb
```

| Script | Does |
|---|---|
| `env.sh` | All pinned versions and paths (single source of truth) |
| `00_bootstrap_ubuntu.sh` | System packages, Rust Android target, Android SDK/NDK |
| `10_build_compiler.sh` | TVM + `mlc_llm` from source into `~/.mlc-s25/venv` |
| `20_convert_weights.sh` | Converts `"source": "convert"` models in `s25-models.json` |
| `30_compile_and_package.sh` | Per-model Adreno libraries, then `mlc_llm package` (runtime via NDK) |
| `40_build_apk.sh` | Release keystore (first run), R8 release APK, lint gate |
| `50_verify_apk.sh` | Signature, targetSdk, permission allow-list, manifest flags, 16 KB alignment, R8 keep check |
| `60_install_to_phone.sh` | `adb install -r` + side-loads bundled weights |

Models are listed in `s25-models.json`: `Qwen3-4B` (downloaded by the app)
and `Huihui-Qwen3-4B-Instruct-2507-abliterated` (an uncensored finetune,
converted locally and side-loaded). Add entries there; each gets its own
library, since `rope_theta` and the context/prefill sizes are compiled into
the kernels.

## Security and permission changes vs upstream MLCChat

| Area | Upstream | This build | Why |
|---|---|---|---|
| Runtime permissions | Prompts for photos + camera on every launch | **None requested** | Photo Picker returns a per-item grant; camera via `ACTION_IMAGE_CAPTURE` |
| `CAMERA` | Requested at runtime but **not declared** (request silently failed) | Not declared, actively removed | Declaring it would make the capture intent throw until granted |
| `READ_MEDIA_IMAGES` | Declared + requested | Removed | Photo Picker needs no permission |
| `WRITE_EXTERNAL_STORAGE` | Declared (maxSdk 32) | Removed | `getExternalFilesDir()` needs none |
| Camera output | Inserted into the shared gallery (MediaStore) | App-private cache via `FileProvider` | Photos sent to the model do not leak into the gallery or cloud photo sync |
| Backup | `allowBackup=true`, empty rules | `allowBackup=false`, all domains excluded | Local-LLM chats stay on the device |
| Network | Cleartext allowed by default config, user CAs | HTTPS only, system CAs only | Model downloads cannot be read or swapped by a user-installed MITM CA |
| Download filenames | Remote JSON names written as `File(dir, name)` | `SafeIO.child`: one plain segment, canonical-path check | A malicious model repo could write `../` paths elsewhere in app storage |
| Download errors | Uncaught exception on worker thread crashes the app; no timeouts; HTTP errors saved as files | Caught, timeouts (15 s / 60 s), non-2xx rejected, task stays queued | Stability and integrity |
| Release build | Not minified, not signed | R8 + resource shrinking, v2+ signed with local release key | Size, and installable release builds |
| Dependencies | JitPack for all groups, no checksums | JitPack limited to one group, every artifact SHA-256 pinned, wrapper SHA-256 pinned | Supply chain |
| Engine module deps | appcompat + material (unused) | Only kotlinx serialization + coroutines | Smaller attack surface |

## Android platform requirements covered

* compileSdk/targetSdk **37** (Android 17), minSdk 26.
* Edge-to-edge (enforced at targetSdk 35+): `enableEdgeToEdge()` + safe-drawing insets; deprecated `statusBarColor` removed.
* Predictive back: `enableOnBackInvokedCallback="true"`.
* 16 KB page size: NDK r30 links with 16 KB segment alignment; `.so` stored uncompressed and 16 KB-aligned; checked by `50_verify_apk.sh`.
* Java/Kotlin bytecode 17, AGP 9 built-in Kotlin, Compose BOM 2026.09.00.
* Lint runs on the release variant and fails the build on errors.

## Keeping up with security updates

1. Upstream code: `git remote add upstream https://github.com/mlc-ai/mlc-llm`,
   then `git fetch upstream && git merge upstream/main`, and
   `git submodule update --init --recursive`. Rerun `build_all.sh`.
2. Android toolchain: bump versions in `env.sh` (NDK, build-tools, platform,
   cmdline-tools SHA-256 from `https://dl.google.com/android/repository/repository2-3.xml`).
3. Gradle dependencies: edit versions, then
   `./gradlew --write-verification-metadata sha256 :app:assembleRelease :app:lintRelease`
   and review the diff of `gradle/verification-metadata.xml` before committing.
4. Docker base image: bump the pinned digest in `Dockerfile`.
5. Reinstall with `60_install_to_phone.sh` (`install -r` keeps downloaded models
   as long as the same signing key is used).

## Failure modes

| Symptom | Layer | Likely cause | Action |
|---|---|---|---|
| `10_build_compiler.sh` killed | laptop | RAM exhausted during TVM link | `JOBS=2` |
| `Model lib ... is not supported` in app | app config | `model_lib` in app config not linked into the APK | Rerun 30 then 40 |
| App closes on model load, logcat shows `clCreateContext`/OpenCL errors | runtime/driver | OpenCL not exposed to the app, or kernel too large for Adreno limits | Check `uses-native-library` in manifest; lower `prefill_chunk_size` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | signing | Different key than the installed build | Uninstall first (deletes downloaded models), keep the keystore backed up |
| Download fails "Refusing non-HTTPS" | app | Model URL is `http://` or a local path | Use `HF://` models, or `bundle_weight` + `60_install_to_phone.sh` |
| Strict dependency verification fails | build | A dependency changed or was tampered with | Investigate before regenerating the metadata |
