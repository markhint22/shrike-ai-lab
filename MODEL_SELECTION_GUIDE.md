# Model Selection: What Can Your RTX 2060 Actually Handle?

**Your GPU:** RTX 2060 (4GB VRAM)  
**Your Goals:** Train models for code/test tasks without crashes

---

## Three Viable Options for Training on RTX 2060

### Option 1: TinyLlama 1.1B (Currently Using) ✅ SAFE

```
Model:      TinyLlama 1.1B
VRAM Used:  ~1-2GB training
Crashes:    No
Speed:      ~200 examples/hour
Quality:    Weak for code tasks (1.1B is very small)
Safety:     Maximum (tons of headroom)

Pros:
  ✅ Fastest training (2x faster than Phi-3 Mini)
  ✅ Lowest memory pressure (half the VRAM needed)
  ✅ Zero crash risk
  ✅ Good for general Q&A tasks

Cons:
  ❌ Only 1.1B parameters (very limited code understanding)
  ❌ Poor at selector optimization (might generate invalid CSS)
  ❌ Weak at failure analysis (less context understanding)
  ❌ May not learn well from code examples

Recommendation: ❌ TOO SMALL for SpecPilot selector optimization
```

### Option 2: Phi-3 Mini 3.8B (RECOMMENDED) ✅ BEST BALANCE

```
Model:      Phi-3 Mini 3.8B
VRAM Used:  ~3-4GB training
Crashes:    No (fits GPU exactly)
Speed:      ~100 examples/hour
Quality:    Good for code (designed by Microsoft for efficiency)
Safety:     High (GPU at capacity but stable)

Pros:
  ✅ 3.5x bigger than TinyLlama (better understanding)
  ✅ Microsoft-designed for code understanding
  ✅ Fits your GPU exactly (no overflow)
  ✅ Still won't crash
  ✅ Still acceptable training speed

Cons:
  ⚠️ GPU at full capacity (zero headroom)
  ⚠️ Slower than TinyLlama (still fast though)
  ⚠️ Not as good as 7B models (but you can't run those)

Recommendation: ✅ PERFECT for your hardware + goals
```

### Option 3: CodeLlama 7B with Monitoring ⚠️ RISKY BUT POSSIBLE

```
Model:      CodeLlama 7B
VRAM Used:  ~6-8GB training (with aggressive batch size 1)
Crashes:    Low (with memory monitoring enabled)
Speed:      ~50 examples/hour (2x slower than Phi-3)
Quality:    Excellent for code (purpose-built for code)
Safety:     Medium (requires active monitoring)

Pros:
  ✅ Best code understanding available
  ✅ Excellent for CSS selectors
  ✅ Best failure diagnosis capability
  ✅ Higher quality training results

Cons:
  ❌ Requires my crash monitoring wrapper to work safely
  ❌ GPU at 150% capacity (CPU offloading required)
  ❌ Much slower training (100+ hours vs 50 hours)
  ❌ Must avoid long overnight runs without monitoring
  ❌ Still risky if background processes spike

Recommendation: ⚠️ Only if you absolutely need best code quality + willing to accept 2x slower training
```

---

## Task-Specific Analysis: Will Your Current Model Work?

### SpecPilot: Selector Optimization

**Task:** Find reliable CSS selectors for HTML elements
```
Example:
  Input:  "<div id='login' class='btn-primary'>Login</div>"
          "Current selector: .btn (unreliable, matches other buttons)"
  Output: "#login or .btn-primary (more specific, won't match others)"
```

**Code Understanding Needed:** Medium-High
- Must parse HTML structure
- Must understand CSS selector specificity
- Must avoid over-fitting to one example

**Model Performance:**
- TinyLlama 1.1B: ❌ Likely generates invalid CSS or misses specificity
- Phi-3 Mini 3.8B: ✅ Should handle this well
- CodeLlama 7B: ✅✅ Excellent, best option

**Recommendation:** Phi-3 Mini minimum, CodeLlama 7B if you can tolerate slower training

### GitLark: Code Review

**Task:** Review code and suggest improvements

**Code Understanding Needed:** Medium
- Must understand code structure
- Must identify common issues
- Must suggest idiomatic patterns

**Model Performance:**
- TinyLlama 1.1B: ⚠️ Very basic, might miss subtleties
- Phi-3 Mini 3.8B: ✅ Should work well
- CodeLlama 7B: ✅✅ Excellent

**Recommendation:** Phi-3 Mini acceptable, CodeLlama 7B better

### BillWatch: Bill Classification

**Task:** Classify bills by type (healthcare, infrastructure, etc.)

**Code Understanding Needed:** Low (mostly NLP/classification)
- Must understand semantic meaning
- Pattern recognition
- Category mapping

**Model Performance:**
- TinyLlama 1.1B: ✅ Actually okay for this (not code-heavy)
- Phi-3 Mini 3.8B: ✅✅ Excellent
- CodeLlama 7B: ✅✅ Overkill but excellent

**Recommendation:** TinyLlama adequate, Phi-3 Mini ideal

---

## My Recommendation

### Path A: Safe & Proven (RECOMMENDED)
**Switch from TinyLlama 1.1B → Phi-3 Mini 3.8B**

✅ Pros:
- 3.5x bigger, much better code understanding
- Still fits GPU without crashes
- Training still reasonably fast (~100 ex/hr)
- Addresses your actual problem (crashes + weak code quality)
- No monitoring overhead

❌ Cons:
- Slightly slower training than TinyLlama

**When to do this:**
- Right now (you're seeing weak results from TinyLlama)
- Or after one more TinyLlama run to compare

### Path B: Maximum Quality (If Patience Allows)
**Upgrade to CodeLlama 7B with memory monitoring**

✅ Pros:
- Best possible code quality
- Excellent for selector optimization

❌ Cons:
- 2x slower training (but you have monitoring now)
- Requires active oversight (no unattended 18-hour runs)
- Still tight on memory

**When to do this:**
- Only if Phi-3 Mini results aren't good enough
- And you're willing to accept 100+ hour training runs
- And you keep my memory monitoring enabled

### Path C: Don't Change (WORST)
**Keep TinyLlama 1.1B**

❌ Pros:
- Fastest training
- Zero crash risk

❌ Cons:
- Model is too small for code tasks
- Selector optimization will be poor quality
- You're optimizing for the wrong metric (speed vs quality)

---

## Decision Matrix

| Priority | Best Model | Why |
|----------|-----------|-----|
| **Avoid crashes** | TinyLlama 1.1B | Fits GPU, no memory pressure |
| **Reasonable speed** | Phi-3 Mini 3.8B | 3.5x bigger than TinyLlama, still fast |
| **Best quality** | CodeLlama 7B | Purpose-built for code, slowest though |
| **Balance all three** | **Phi-3 Mini 3.8B** | ← THIS ONE |

---

## Implementation: How to Switch to Phi-3 Mini

### Step 1: Download the Model (5 minutes)
```powershell
ollama pull phi3:mini
```

### Step 2: Update Your Training Config
**File:** `training/queue/nightly_jobs.json`

Change all jobs from:
```json
"base_model": "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
```

To:
```json
"base_model": "unsloth/phi-3-mini-4k-instruct"
```

### Step 3: Test with One Job (10 minutes)
```powershell
cd d:\LocalProjects\shrike-ai-lab

# Test selector_optimization with Phi-3 Mini
python training/specpilot/finetune.py `
    --model unsloth/phi-3-mini-4k-instruct `
    --data training/specpilot/data/selector_optimization.jsonl `
    --epochs 1 `
    --batch-size 1
```

**Expected:** Completes in 5-10 minutes, no crashes, GPU at 4GB max.

### Step 4: If Successful, Run Full Queue
```powershell
python scripts/train_queue.py `
    --jobs-file training/queue/nightly_jobs.json `
    --max-hours 18
```

**Expected:** All 4 projects train overnight without crashes, ~18 hours total.

---

## Performance Comparison (Rough Estimates)

| Metric | TinyLlama 1.1B | Phi-3 Mini 3.8B | CodeLlama 7B |
|--------|---|---|---|
| Training Speed (ex/hr) | 200 | 100 | 50 |
| Time for 5k examples | 25 hours | 50 hours | 100 hours |
| Selector Quality | 🟡 Poor | 🟢 Good | 🟢🟢 Excellent |
| Code Understanding | 🔴 Weak | 🟢 Good | 🟢🟢 Excellent |
| Crash Risk | 🟢 None | 🟢 None | 🟡 Low (with monitoring) |
| GPU Fit | 🟢 Lots room | 🟢 Perfect fit | 🟡 Overflow to CPU |

---

## Bottom Line

**Current:** TinyLlama 1.1B (too small, won't crash)  
**Better:** Phi-3 Mini 3.8B (bigger, still fits, good quality)  
**Best:** CodeLlama 7B (best quality, but slower and needs monitoring)

**My recommendation:** **Upgrade to Phi-3 Mini 3.8B.** It's the sweet spot — 3.5x bigger than TinyLlama (much better for code), still fits your GPU perfectly, and won't crash. Training will take ~50 hours instead of ~25 hours, but you'll get much better results.

Want me to update your training config to Phi-3 Mini?
