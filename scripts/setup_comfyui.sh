#!/usr/bin/env bash
# GPU-FREE setup of a ComfyUI pixel-art stack for xlite game assets. Installs to the
# secondary drive (space), python3.12 venv (torch has 3.12 wheels; system 3.14 does
# not), torch cu124, ComfyUI + LayerDiffuse (transparent bg) + PixelArt-Detector
# (snap to true pixel grid + limited palette), and pre-downloads SDXL base + the
# Pixel Art XL LoRA + LayerDiffuse weights. Does NOT touch the GPU or the queue —
# only the generation step (separate window) needs the card. Idempotent-ish, resumable
# downloads. Poll: reports/comfy-setup.out
set -uo pipefail
ROOT=/run/media/mhintermeister/secondary_drive1/comfy
C=$ROOT/ComfyUI
OUT=/home/mhintermeister/overnight-queue/reports/comfy-setup.out
exec 9>/tmp/comfy_setup.lock
if ! flock -n 9; then echo "setup already running" >&2; exit 0; fi
mkdir -p "$ROOT"; : > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
dl(){ # url dest
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then log "  have $(basename "$dest") ($(du -h "$dest"|cut -f1))"; return; fi
  log "  downloading $(basename "$dest") ..."
  curl -fL -C - --retry 3 --retry-delay 5 -o "$dest" "$url" >>"$OUT" 2>&1 \
    && log "  done $(basename "$dest") ($(du -h "$dest"|cut -f1))" \
    || log "  FAILED $(basename "$dest")"
}

log "=== ComfyUI pixel-art setup START ==="

# 1. ComfyUI
if [ ! -d "$C/.git" ]; then
  log "cloning ComfyUI"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI "$C" >>"$OUT" 2>&1
else log "ComfyUI already cloned"; fi

# 2. venv on python3.12
if [ ! -f "$C/.venv/bin/python" ]; then
  log "creating python3.12 venv"
  /usr/bin/python3.12 -m venv "$C/.venv" >>"$OUT" 2>&1
fi
PY="$C/.venv/bin/python"
"$PY" -m pip install --upgrade pip wheel >>"$OUT" 2>&1

# 3. torch (CUDA 12.4 wheels — matches driver 580)
if ! "$PY" -c "import torch" 2>/dev/null; then
  log "installing torch cu124 (large)"
  "$PY" -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124 >>"$OUT" 2>&1 \
    && log "torch: $("$PY" -c 'import torch;print(torch.__version__)' 2>/dev/null)" || log "torch install FAILED"
else log "torch present: $("$PY" -c 'import torch;print(torch.__version__)')"; fi

# 4. ComfyUI requirements
log "installing ComfyUI requirements"
"$PY" -m pip install -r "$C/requirements.txt" >>"$OUT" 2>&1 && log "comfy reqs ok" || log "comfy reqs FAILED"

# 5. custom nodes
CN="$C/custom_nodes"; mkdir -p "$CN"
for spec in \
  "https://github.com/huchenlei/ComfyUI-layerdiffuse ComfyUI-layerdiffuse" \
  "https://github.com/Astropulse/ComfyUI_PixelArt_Detector ComfyUI_PixelArt_Detector"; do
  set -- $spec; url="$1"; name="$2"
  if [ ! -d "$CN/$name/.git" ]; then log "cloning node $name"; git clone --depth 1 "$url" "$CN/$name" >>"$OUT" 2>&1; fi
  [ -f "$CN/$name/requirements.txt" ] && "$PY" -m pip install -r "$CN/$name/requirements.txt" >>"$OUT" 2>&1
done

# 6. models
mkdir -p "$C/models/checkpoints" "$C/models/loras" "$C/models/layer_model"
dl "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
   "$C/models/checkpoints/sd_xl_base_1.0.safetensors"
dl "https://huggingface.co/nerijs/pixel-art-xl/resolve/main/pixel-art-xl.safetensors" \
   "$C/models/loras/pixel-art-xl.safetensors"
dl "https://huggingface.co/LayerDiffusion/layerdiffusion-v1/resolve/main/layer_xl_transparent_attn.safetensors" \
   "$C/models/layer_model/layer_xl_transparent_attn.safetensors"
dl "https://huggingface.co/LayerDiffusion/layerdiffusion-v1/resolve/main/vae_transparent_decoder.safetensors" \
   "$C/models/layer_model/vae_transparent_decoder.safetensors"

log "=== disk after: $(du -sh "$C/models" 2>/dev/null | cut -f1) models ==="
log "torch cuda check (import only, no GPU alloc): $("$PY" -c 'import torch;print("cuda_build="+str(torch.version.cuda))' 2>/dev/null)"
log "=== SETUP DONE ==="
