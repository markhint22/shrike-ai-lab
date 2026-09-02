#!/usr/bin/env bash
# Download the unsloth UD-IQ4_XS quant (14.3GB, smaller than our 17GB Q4_K_M -> the
# one real speed candidate) + its separate MTP head, to bench tok/s vs current.
# WAITS for the ComfyUI SDXL download to finish first so the two don't split
# bandwidth (art is the priority deliverable). flock-guarded, resumable.
set -uo pipefail
MD=/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/models/deepflash
SDXL=/run/media/mhintermeister/secondary_drive1/comfy/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors
OUT=/home/mhintermeister/overnight-queue/reports/fetch-iq4xs.out
exec 9>/tmp/fetch_iq4xs.lock
if ! flock -n 9; then echo "already running" >&2; exit 0; fi
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }
dl(){ local url="$1" dest="$2"
  [ -s "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null||echo 0)" -gt 1000000000 ] && { log "have $(basename "$dest")"; return; }
  log "downloading $(basename "$dest")"
  curl -fL -C - --retry 4 --retry-delay 8 -o "$dest" "$url" >>"$OUT" 2>&1 \
    && log "done $(basename "$dest") ($(du -h "$dest"|cut -f1))" || log "FAILED $(basename "$dest")"
}

# wait until SDXL is fully downloaded (>6GB) so art keeps bandwidth priority
log "waiting for SDXL art download to finish before pulling the quant..."
for i in $(seq 1 120); do
  sz=$(stat -c%s "$SDXL" 2>/dev/null || echo 0)
  [ "$sz" -gt 6000000000 ] && { log "SDXL done (${sz} bytes) — proceeding"; break; }
  sleep 30
done

dl "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-IQ4_XS.gguf" \
   "$MD/Qwen3.8-27B-UD-IQ4_XS.gguf"
dl "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/MTP/mtp-Qwen3.8-27B-Q4_0.gguf" \
   "$MD/mtp-Qwen3.8-27B-Q4_0.gguf"
log "=== FETCH DONE ==="
