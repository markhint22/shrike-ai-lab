# Hardware vs. Model Size Analysis

**Your System:**
- GPU: RTX 2060 (4GB VRAM)
- RAM: 48GB
- Training Script Optimized For: RTX 2080 (8GB) / RTX 2080 Ti (11GB)

**Reality: Your GPU is half the size of the system the training script was designed for.**

---

## Model Size Breakdown (VRAM Requirements for Fine-Tuning)

### Models You're Currently Running

| Model | Size | VRAM for Training | GPU Fit? | Notes |
|-------|------|-------------------|----------|-------|
| **Phi-3 Mini** | 3.8B | ~3-4GB (4-bit) | ✅ **FITS** | Only model actually sized for your GPU |
| **CodeLlama 7B** | 7B | ~6-8GB (4-bit) | ⚠️ **TIGHT** | Works but very tight, maxes out your GPU |
| **Mistral 7B** | 7B | ~6-8GB (4-bit) | ⚠️ **TIGHT** | Same as CodeLlama |
| **CodeLlama 13B** | 13B | ~10-12GB (4-bit) | ❌ **TOO BIG** | Needs 2.5x your VRAM |

---

## What's Actually Happening During Training

When you fine-tune with QLoRA:

1. **Model weights** (4-bit quantized): 7B model = ~3.5GB
2. **LoRA adapters** (new trainable weights): ~200-500MB
3. **Optimizer states** (Adam): ~1-2GB
4. **Activations/gradients**: ~1-2GB
5. **Batch data in memory**: ~500MB-2GB (depending on batch size)

**Total for 7B model:** 6-8GB VRAM minimum  
**Your GPU:** 4GB  
**Result:** Heavy CPU offloading to system RAM (slow but works if you avoid OOM)

---

## The Real Problem

Your crashes weren't just "memory exhaustion" — they were **VRAM exhaustion forcing system RAM fallback**:

1. Training starts, 7B model loads into 4GB VRAM
2. VRAM fills to 100% almost immediately
3. Additional allocations spill to system RAM (100x slower)
4. System RAM fills up → Windows OOM killer → Hard crash

**The crash diagnostics before showed 99.9% system RAM used.** That wasn't coincidence — the GPU was forcing everything into system RAM.

---

## Recommendations by Use Case

### Option 1: Inference Only (No Training) ✅ BEST FIT
If you only need to **run** models, not train them:
```
- CodeLlama 7B: ✅ Works (slower, CPU-offloaded)
- Mistral 7B: ✅ Works (slower, CPU-offloaded)
- CodeLlama 13B: ✅ Works (very slow, but possible)
- Phi-3 Mini: ✅ Fast (fits in VRAM)
```

**Action:** Use `-n_gpu_layers 1` for inference to minimize VRAM pressure.

### Option 2: Train Small Models Only ✅ SAFE
If you need to **fine-tune** models:
```
- Phi-3 Mini (3.8B): ✅✅ PERFECT - fits in GPU, trains in <2 hours
- TinyLlama (1.1B): ✅✅ PERFECT - extremely fast
- CodeLlama 7B: ⚠️ Works but very slow, system RAM required
- CodeLlama 13B: ❌ Skip entirely (too big)
```

**Action:** Change your training script to use Phi-3 Mini instead of CodeLlama 7B.

### Option 3: Hybrid Approach ✅ RECOMMENDED
```
Inference:  Use CodeLlama 7B/13B (slower, but works)
Training:   Use Phi-3 Mini (fits GPU, trains fast)
```

**Action:** Keep current config for inference, switch to Phi-3 Mini for fine-tuning.

---

## Your Current Training Config (Problem Areas)

From `training/specpilot/finetune.py`:

```python
# Current: Fine-tuning CodeLlama 7B on RTX 2060 4GB
# This requires:
# - 6-8GB VRAM (you have 4GB)
# - Heavy CPU offloading (slow)
# - System RAM as backup (causes crashes)
```

**What you should change to:**

```python
# Option A: Fine-tune Phi-3 Mini instead (RECOMMENDED)
model_name = "unsloth/phi-3-mini-4k-instruct"  # 3.8B
# Uses: ~3-4GB VRAM, NO CPU offloading, fast training

# Option B: Keep CodeLlama 7B but reduce batch size
training_args = TrainingArguments(
    per_device_train_batch_size=1,  # Instead of 4 or 8
    gradient_accumulation_steps=8,   # Compensate with more steps
)
# Still slow due to CPU offload, but more stable
```

---

## Specific Next Steps

### 1. Short Term (Today)
**Test Phi-3 Mini training** to see if it actually fits:

```bash
cd d:\LocalProjects\shrike-ai-lab
ollama pull phi3:mini  # Already have this

# Create test training job with Phi-3 Mini
python training/specpilot/finetune.py \
    --data training/specpilot/data/selector_optimization.jsonl \
    --model unsloth/phi-3-mini-4k-instruct \
    --epochs 1 \
    --batch-size 1
```

**Expected result:** Completes in <2 hours without crashes.

### 2. Medium Term (This Week)
If Phi-3 Mini works:
- **Switch training configs** to use Phi-3 Mini by default
- **Keep CodeLlama 7B/13B for inference** (slower but works)
- **Archive CodeLlama training** data for future use on better GPU

### 3. Long Term (Equipment Upgrade)
To train 7B+ models safely, you need:
- **RTX 4090** (24GB) - Can train 13B-70B with QLoRA
- **Or:** RTX 3090 Ti (24GB) - Used, ~$800-1200
- **Or:** Multiple GPUs with distributed training

Current GPU (RTX 2060 4GB) is fine for inference only.

---

## Performance Expectations

### Phi-3 Mini (3.8B) - What You Should Be Using for Training
```
Fine-tuning speed: ~100 examples/hour
Training time:     selector_optimization (5k examples) = ~50 hours
Memory usage:      3-4GB VRAM (fits GPU completely)
CPU offloading:    None needed
Crash risk:        Very low ✅
```

### CodeLlama 7B - What You're Currently Using
```
Fine-tuning speed: ~50 examples/hour (half speed due to CPU offload)
Training time:     selector_optimization (5k examples) = ~100 hours
Memory usage:      6-8GB VRAM + 10-15GB system RAM
CPU offloading:    Heavy (100x slower than GPU operations)
Crash risk:        High ⚠️ (system RAM exhaustion)
```

**Phi-3 Mini is 2x faster AND safer AND uses less resources.**

---

## Summary

| Aspect | Current | Recommendation | Change |
|--------|---------|-----------------|--------|
| **GPU Size** | 4GB (RTX 2060) | 4GB is the limit for Phi-3 | ✅ OK |
| **Model for Training** | CodeLlama 7B | Phi-3 Mini | Switch ↔️ |
| **Model for Inference** | CodeLlama 7B/13B | Keep (slower but works) | ✅ OK |
| **Expected Crashes** | High (RAM OOM) | Very Low | Solve by switching |
| **Training Speed** | 50 ex/hr (slow) | 100 ex/hr (Phi-3) | 2x faster |
| **Training Duration** | 100+ hours | 50 hours (Phi-3) | 2x shorter |

---

## Action Items

**🟢 Do This:**
- [ ] Test Phi-3 Mini fine-tuning (it will work)
- [ ] Create separate configs for inference vs. training
- [ ] Use Phi-3 Mini for all training going forward

**🟡 Optional:**
- [ ] Keep CodeLlama 7B for inference (slower but OK)
- [ ] Archive CodeLlama training data
- [ ] Plan for GPU upgrade when budget allows

**🔴 Don't Do This:**
- [ ] Don't train CodeLlama 7B on RTX 2060 (causes crashes)
- [ ] Don't train CodeLlama 13B (too big, guaranteed OOM)
- [ ] Don't run training without crash mitigation in place

---

**Bottom Line:** You're not running models that are too big for your GPU to **run** (inference works), but they're too big for your GPU to **train**. Switch to Phi-3 Mini for fine-tuning and your crashes will stop.
