#!/usr/bin/env python3
"""
Unified Fine-tuning Pipeline

Single entry point to train models for any Shrike Labs project.
Handles data loading, model selection, training, and export.
"""

import os
import sys
import json
import argparse
import importlib.util
import inspect
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional


# Project configurations
PROJECT_CONFIGS = {
    "specpilot": {
        "tasks": [
            "selector_optimization",
            "test_generation",
            "failure_analysis",
            # Phase 2 capsules
            "flow_analysis",
            "test_building",
        ],
        "base_model": "codellama/CodeLlama-7b-hf",
        "max_seq_length": 2048,
        "description": "Test automation agent",
    },
    "gitlark": {
        "tasks": [
            "code_explanation",
            "pr_description",
            "code_review",
            "commit_message",
            # Phase 2 capsules
            "repo_intelligence",
            "memdiff",
        ],
        "base_model": "codellama/CodeLlama-7b-hf",
        "max_seq_length": 2048,
        "description": "AI code workspace",
    },
    "billwatch": {
        "tasks": [
            "summarization",
            "classification",
            "impact",
            # Phase 2 capsules
            "bill_background",
            "article_relevance",
        ],
        "base_model": "mistralai/Mistral-7B-Instruct-v0.2",
        "max_seq_length": 2048,  # Reduced from 4096 to prevent memory crashes on CPU training
        "description": "Legislation tracker",
    },
    "shared": {
        "tasks": [
            "code_review",
            # Cross-project skill capsules
            "moderation",
        ],
        "base_model": "codellama/CodeLlama-7b-hf",
        "max_seq_length": 2048,
        "description": "Cross-project models",
    },
}


DATA_FILE_OVERRIDES = {
    ("billwatch", "summarization"): "bill_summaries.jsonl",
    ("billwatch", "bill_background"): "bill_background.jsonl",
    ("billwatch", "article_relevance"): "article_relevance.jsonl",
    ("gitlark", "repo_intelligence"): "repo_intelligence.jsonl",
    ("gitlark", "memdiff"): "memdiff.jsonl",
    ("specpilot", "flow_analysis"): "flow_analysis.jsonl",
    ("specpilot", "test_building"): "test_building.jsonl",
    ("shared", "moderation"): "moderation.jsonl",
}


REQUIRED_MODULES_UNSLOTH = ["unsloth", "trl", "transformers", "datasets"]
REQUIRED_MODULES_HF = ["transformers", "datasets", "peft", "torch"]


def _is_module_available(module_name: str) -> bool:
    """Check whether a Python module can be imported."""
    return importlib.util.find_spec(module_name) is not None


def _check_modules(module_names):
    """Return list of missing modules."""
    return [name for name in module_names if not _is_module_available(name)]


def _detect_lora_target_modules(model) -> list[str]:
    """Detect LoRA target module names for common decoder-only architectures."""
    preferred = [
        "q_proj",
        "k_proj",
        "v_proj",
        "o_proj",
        "gate_proj",
        "up_proj",
        "down_proj",
        "c_attn",
        "c_proj",
        "query_key_value",
    ]

    discovered = set()
    for name, _ in model.named_modules():
        suffix = name.split(".")[-1]
        if suffix in preferred:
            discovered.add(suffix)

    ordered = [name for name in preferred if name in discovered]
    return ordered


def cleanup_stale_hf_model_locks(base_model: str, stale_after_seconds: int = 7200) -> int:
    """Remove stale Hugging Face lock files for a specific model.

    Prior crashed runs can leave lock files that cause future runs to wait.
    """
    lock_dir = (
        Path.home()
        / ".cache"
        / "huggingface"
        / "hub"
        / ".locks"
        / f"models--{base_model.replace('/', '--')}"
    )
    if not lock_dir.exists():
        return 0

    removed = 0
    now = time.time()
    for lock_file in lock_dir.glob("*.lock"):
        try:
            age_seconds = now - lock_file.stat().st_mtime
        except OSError:
            continue

        if age_seconds >= stale_after_seconds:
            try:
                lock_file.unlink()
                removed += 1
            except OSError:
                continue

    return removed


def configure_hf_download_env() -> None:
    """Set conservative HF env defaults that improve download throughput/reliability."""
    os.environ.setdefault("HF_XET_HIGH_PERFORMANCE", "1")
    os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "120")
    os.environ.setdefault("HF_HUB_ETAG_TIMEOUT", "30")
    os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
    # Prevent UnicodeEncodeError when emoji from finetune.py modules hits the cp1252 log file.
    # Must reconfigure the live streams, not just set the env var.
    import sys
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass


def prefetch_model_snapshot(base_model: str, hf_cache_dir: Path) -> str:
    """Warm model files into cache and return a local snapshot path when possible."""
    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        return base_model

    try:
        snapshot_path = snapshot_download(
            repo_id=base_model,
            cache_dir=str(hf_cache_dir),
            resume_download=True,
            max_workers=12,
        )
        print(f"Using local snapshot: {snapshot_path}")
        return snapshot_path
    except Exception as exc:
        print(f"Snapshot prefetch warning: {exc}")
        return base_model


def get_data_path(project: str, task: str) -> Path:
    """Get path to training data for a project/task."""
    base = Path(__file__).parent.parent / "training" / project / "data"

    override_name = DATA_FILE_OVERRIDES.get((project, task))
    if override_name:
        override_path = base / override_name
        if override_path.exists():
            return override_path
    
    # Common naming patterns
    patterns = [
        f"{task}.jsonl",
        f"{task}s.jsonl",
        f"{task.replace('_', '-')}.jsonl",
    ]
    
    for pattern in patterns:
        path = base / pattern
        if path.exists():
            return path
    
    raise FileNotFoundError(f"No data found for {project}/{task}")


def get_model_output_dir(project: str, task: str, version: str) -> Path:
    """Get output directory for trained model."""
    base = Path(__file__).parent.parent / "models"
    return base / f"{project}-{task}-{version}"


def count_examples(data_path: Path) -> int:
    """Count training examples in JSONL file."""
    count = 0
    with open(data_path) as f:
        for line in f:
            if line.strip():
                count += 1
    return count


def validate_project_task(project: str, task: str) -> bool:
    """Validate project and task exist."""
    if project not in PROJECT_CONFIGS:
        print(f"Unknown project: {project}")
        print(f"Available: {list(PROJECT_CONFIGS.keys())}")
        return False
    
    if task not in PROJECT_CONFIGS[project]["tasks"]:
        print(f"Unknown task for {project}: {task}")
        print(f"Available: {PROJECT_CONFIGS[project]['tasks']}")
        return False
    
    return True


def train_model(
    project: str,
    task: str,
    version: str = "v1",
    epochs: int = 3,
    batch_size: int = 4,
    learning_rate: float = 2e-4,
    lora_r: int = 16,
    engine: str = "auto",
    base_model_override: Optional[str] = None,
    max_seq_length_override: Optional[int] = None,
    max_steps_override: Optional[int] = None,
    dry_run: bool = False,
) -> Dict[str, Any]:
    """
    Train a model for a specific project and task.
    
    Returns training metadata.
    """
    if not validate_project_task(project, task):
        return {"status": "error", "message": "Invalid project/task"}
    
    config = PROJECT_CONFIGS[project]
    base_model = base_model_override or config["base_model"]
    max_seq_length = max_seq_length_override or config["max_seq_length"]
    data_path = get_data_path(project, task)
    output_dir = get_model_output_dir(project, task, version)
    
    num_examples = count_examples(data_path)
    
    print(f"\n{'='*60}")
    print(f"Unified Fine-tuning Pipeline")
    print(f"{'='*60}")
    print(f"Project:     {project} ({config['description']})")
    print(f"Task:        {task}")
    print(f"Version:     {version}")
    print(f"Base Model:  {base_model}")
    print(f"Data:        {data_path} ({num_examples} examples)")
    print(f"Output:      {output_dir}")
    print(f"{'='*60}")
    print(f"Hyperparameters:")
    print(f"  Epochs:        {epochs}")
    print(f"  Batch Size:    {batch_size}")
    print(f"  Learning Rate: {learning_rate}")
    print(f"  LoRA Rank:     {lora_r}")
    print(f"  Max Seq Len:   {max_seq_length}")
    print(f"{'='*60}\n")
    
    if dry_run:
        print("DRY RUN - Would train with above configuration")
        return {"status": "dry_run", "config": config}

    missing_unsloth = _check_modules(REQUIRED_MODULES_UNSLOTH)
    missing_hf = _check_modules(REQUIRED_MODULES_HF)

    if engine not in {"auto", "unsloth", "hf"}:
        return {"status": "error", "message": f"Unknown engine: {engine}"}

    if engine == "unsloth":
        selected_engine = "unsloth"
    elif engine == "hf":
        selected_engine = "hf"
    else:
        selected_engine = "unsloth" if not missing_unsloth else "hf"

    if selected_engine == "unsloth" and missing_unsloth:
        message = f"Missing dependencies for unsloth engine: {', '.join(missing_unsloth)}"
        print(message)
        print("Install with: pip install unsloth trl transformers datasets")
        return {"status": "error", "message": message}

    if selected_engine == "hf" and missing_hf:
        message = f"Missing dependencies for hf engine: {', '.join(missing_hf)}"
        print(message)
        print("Install with: pip install transformers datasets peft accelerate trl torch")
        return {"status": "error", "message": message}

    print(f"Engine:      {selected_engine}")

    configure_hf_download_env()

    hf_cache_dir = Path(__file__).parent.parent / "training" / "cache" / "hf"
    hf_cache_dir.mkdir(parents=True, exist_ok=True)

    removed_locks = cleanup_stale_hf_model_locks(base_model)
    if removed_locks:
        print(f"Removed {removed_locks} stale HF lock file(s) for {base_model}")

    has_cuda_for_training = False

    if selected_engine == "unsloth":
        from unsloth import FastLanguageModel
        from trl import SFTTrainer
        from transformers import TrainingArguments
        from datasets import Dataset

        # Load base model
        print(f"Loading base model: {base_model}...")
        model, tokenizer = FastLanguageModel.from_pretrained(
            model_name=base_model,
            max_seq_length=max_seq_length,
            dtype=None,
            load_in_4bit=True,
        )

        # Add LoRA
        model = FastLanguageModel.get_peft_model(
            model,
            r=lora_r,
            target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                           "gate_proj", "up_proj", "down_proj"],
            lora_alpha=16,
            lora_dropout=0.05,
            bias="none",
            use_gradient_checkpointing=True,
        )
    else:
        import torch
        from datasets import Dataset
        from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
        from transformers import (
            AutoModelForCausalLM,
            AutoTokenizer,
            DataCollatorForLanguageModeling,
            Trainer,
            TrainingArguments,
        )

        has_cuda = torch.cuda.is_available()
        has_cuda_for_training = has_cuda
        print(f"Loading base model: {base_model}...")
        model_source = prefetch_model_snapshot(base_model, hf_cache_dir)
        load_kwargs = {
            "pretrained_model_name_or_path": model_source,
            "torch_dtype": torch.float16 if has_cuda else torch.float32,
            "cache_dir": str(hf_cache_dir),
        }
        if has_cuda:
            load_kwargs["device_map"] = "auto"

        model = AutoModelForCausalLM.from_pretrained(**load_kwargs)
        tokenizer = AutoTokenizer.from_pretrained(
            model_source,
            use_fast=True,
            cache_dir=str(hf_cache_dir),
        )
        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token

        if has_cuda and _is_module_available("bitsandbytes"):
            model = prepare_model_for_kbit_training(model)

        target_modules = _detect_lora_target_modules(model)
        if not target_modules:
            message = "Could not detect compatible LoRA target modules for selected model"
            return {"status": "error", "message": message}

        lora_config = LoraConfig(
            r=lora_r,
            lora_alpha=16,
            target_modules=target_modules,
            lora_dropout=0.05,
            bias="none",
            task_type="CAUSAL_LM",
        )
        model = get_peft_model(model, lora_config)
    
    # Load and format data
    print(f"Loading training data...")
    examples = []
    with open(data_path, encoding="utf-8") as f:
        for line_number, line in enumerate(f, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                examples.append(json.loads(stripped))
            except json.JSONDecodeError as exc:
                preview = stripped[:180]
                raise RuntimeError(
                    "Invalid JSONL record in training data: "
                    f"{data_path} line {line_number}: {exc.msg}. "
                    f"Preview: {preview}"
                ) from exc
    
    # Project-specific formatting
    finetune_module = get_finetune_module(project)
    if finetune_module and hasattr(finetune_module, "load_training_data"):
        # Some project loaders accept (data_path, task), others only (data_path).
        # Introspect once to avoid signature mismatch crashes.
        loader = finetune_module.load_training_data
        try:
            params = inspect.signature(loader).parameters
            if len(params) >= 2:
                formatted = loader(str(data_path), task)
            else:
                formatted = loader(str(data_path))
        except Exception:
            formatted = loader(str(data_path), task)
    else:
        # Default formatting
        formatted = [{"text": json.dumps(e)} for e in examples]
    
    def _normalize_example_to_text(item: dict[str, Any]) -> str:
        """Convert heterogeneous training records to a single text prompt/response format."""
        if "text" in item and item["text"]:
            return str(item["text"])

        instruction = item.get("instruction")
        input_text = item.get("input")
        output_text = item.get("output")

        if instruction is not None and input_text is not None and output_text is not None:
            return (
                "### Instruction:\n"
                f"{instruction}\n\n"
                "### Input:\n"
                f"{input_text}\n\n"
                "### Response:\n"
                f"{output_text}"
            )

        if input_text is not None and output_text is not None:
            return f"Input:\n{input_text}\n\nOutput:\n{output_text}"

        if instruction is not None and output_text is not None:
            return f"Instruction:\n{instruction}\n\nResponse:\n{output_text}"

        return json.dumps(item)

    normalized = [{"text": _normalize_example_to_text(record)} for record in formatted]
    dataset = Dataset.from_list(normalized)

    use_cpu_safe_mode = selected_engine == "hf" and not has_cuda_for_training

    if selected_engine == "hf":
        model_max_positions = getattr(model.config, "max_position_embeddings", None)
        if model_max_positions is None:
            model_max_positions = getattr(model.config, "n_positions", None)

        tokenizer_max_length = getattr(tokenizer, "model_max_length", config["max_seq_length"])
        # Some tokenizers report sentinel max length values; clamp to training config.
        if tokenizer_max_length is None or tokenizer_max_length > 100000:
            tokenizer_max_length = max_seq_length

        effective_max_length = min(
            max_seq_length,
            tokenizer_max_length,
            model_max_positions or max_seq_length,
        )

        if use_cpu_safe_mode:
            cpu_max_seq_len = int(os.environ.get("TRAIN_CPU_MAX_SEQ_LEN", "512"))
            if effective_max_length > cpu_max_seq_len:
                print(
                    f"CPU-safe mode: capping max length from {effective_max_length} "
                    f"to {cpu_max_seq_len}"
                )
                effective_max_length = cpu_max_seq_len

        print(f"Using effective max length: {effective_max_length}")

        def tokenize_example(batch):
            encoded = tokenizer(
                batch["text"],
                truncation=True,
                max_length=effective_max_length,
                padding=(False if use_cpu_safe_mode else "max_length"),
            )
            encoded["labels"] = encoded["input_ids"].copy()
            return encoded

        dataset = dataset.map(tokenize_example)
        dataset.set_format(type="torch", columns=["input_ids", "attention_mask", "labels"])
    
    # Training arguments
    output_dir.mkdir(parents=True, exist_ok=True)
    
    has_cuda_for_args = _is_module_available("torch") and __import__("torch").cuda.is_available()
    # CPU training on Windows is more stable with pin_memory off and conservative Trainer settings.
    use_cpu_safe_mode = selected_engine == "hf" and not has_cuda_for_args
    if use_cpu_safe_mode:
        os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
        os.environ.setdefault("OMP_NUM_THREADS", "1")
        os.environ.setdefault("MKL_NUM_THREADS", "1")

    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=epochs,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=(1 if use_cpu_safe_mode else 4),
        warmup_steps=(1 if use_cpu_safe_mode else 10),
        learning_rate=learning_rate,
        fp16=has_cuda_for_args,
        max_steps=(max_steps_override if max_steps_override is not None else -1),
        logging_steps=10,
        save_strategy="epoch",
        optim=("adafactor" if use_cpu_safe_mode else "adamw_torch"),
        dataloader_pin_memory=(False if use_cpu_safe_mode else True),
        dataloader_num_workers=0,
    )
    
    # Train
    print(f"Starting training for {epochs} epochs...")
    if selected_engine == "unsloth":
        from trl import SFTTrainer
        trainer = SFTTrainer(
            model=model,
            tokenizer=tokenizer,
            train_dataset=dataset,
            dataset_text_field="text",
            max_seq_length=max_seq_length,
            args=training_args,
        )
    else:
        data_collator = DataCollatorForLanguageModeling(tokenizer=tokenizer, mlm=False)
        trainer = Trainer(
            model=model,
            args=training_args,
            train_dataset=dataset,
            data_collator=data_collator,
        )
    
    trainer.train()
    
    # Save
    print(f"Saving model to {output_dir}...")
    model.save_pretrained(output_dir)
    tokenizer.save_pretrained(output_dir)
    
    # Save metadata
    metadata = {
        "project": project,
        "task": task,
        "version": version,
        "base_model": base_model,
        "max_seq_length": max_seq_length,
        "engine": selected_engine,
        "training_examples": num_examples,
        "epochs": epochs,
        "batch_size": batch_size,
        "learning_rate": learning_rate,
        "lora_r": lora_r,
        "trained_at": datetime.now().isoformat(),
    }
    
    with open(output_dir / "training_metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)
    
    print("\n[OK] Training complete!")
    print(f"Model saved to: {output_dir}")
    print(f"\nTo export to Ollama:")
    print(f"  python scripts/export_to_ollama.py --model {output_dir} --name {project}-{task}-{version}")
    
    return {"status": "success", "metadata": metadata}


def get_finetune_module(project: str):
    """Dynamically import project-specific fine-tune module."""
    try:
        import importlib
        module_path = f"training.{project}.finetune"
        return importlib.import_module(module_path)
    except Exception as exc:
        print(f"Project finetune import skipped for {project}: {exc}")
        return None


def list_projects():
    """List available projects and tasks."""
    print("\nAvailable Projects and Tasks\n")
    
    for project, config in PROJECT_CONFIGS.items():
        print(f"  {project}/")
        print(f"    Description: {config['description']}")
        print(f"    Base Model:  {config['base_model']}")
        print(f"    Tasks:")
        for task in config["tasks"]:
            try:
                data_path = get_data_path(project, task)
                count = count_examples(data_path)
                status = f"[OK] {count} examples"
            except FileNotFoundError:
                status = "[MISSING] No data"
            print(f"      - {task}: {status}")
        print()


def print_preflight():
    """Print environment readiness to start model training."""
    print("\nTraining Preflight\n")
    print("Engine dependency checks:")

    missing_unsloth = _check_modules(REQUIRED_MODULES_UNSLOTH)
    missing_hf = _check_modules(REQUIRED_MODULES_HF)

    if missing_unsloth:
        print(f"  unsloth engine: [MISSING] {', '.join(missing_unsloth)}")
    else:
        print("  unsloth engine: [OK] ready")

    if missing_hf:
        print(f"  hf engine:      [MISSING] {', '.join(missing_hf)}")
    else:
        print("  hf engine:      [OK] ready")

    print("\nData availability:")
    for project, config in PROJECT_CONFIGS.items():
        for task in config["tasks"]:
            try:
                data_path = get_data_path(project, task)
                count = count_examples(data_path)
                print(f"  {project}/{task}: [OK] {count} examples ({data_path.name})")
            except FileNotFoundError:
                print(f"  {project}/{task}: [MISSING] no data")

    print("\nSuggested next command:")
    print("  python scripts/train.py --project specpilot --task selector_optimization --engine hf")


def main():
    parser = argparse.ArgumentParser(
        description="Unified Fine-tuning Pipeline for Shrike Labs",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List available projects and tasks
  python train.py --list
  
  # Train GitLark code explanation model
  python train.py --project gitlark --task code_explanation
  
  # Train BillWatch summarizer with custom version
  python train.py --project billwatch --task summarization --version v2
  
  # Dry run to see configuration
  python train.py --project specpilot --task selector_optimization --dry-run
        """
    )
    
    parser.add_argument("--list", action="store_true", help="List available projects and tasks")
    parser.add_argument("--preflight", action="store_true", help="Check training readiness")
    parser.add_argument("--project", "-p", help="Project name (specpilot, gitlark, billwatch, shared)")
    parser.add_argument("--task", "-t", help="Task name (depends on project)")
    parser.add_argument("--version", "-v", default="v1", help="Model version (default: v1)")
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs (default: 3)")
    parser.add_argument("--batch-size", type=int, default=4, help="Batch size (default: 4)")
    parser.add_argument("--learning-rate", type=float, default=2e-4, help="Learning rate (default: 2e-4)")
    parser.add_argument("--lora-r", type=int, default=16, help="LoRA rank (default: 16)")
    parser.add_argument("--engine", choices=["auto", "unsloth", "hf"], default="auto",
                        help="Training engine (default: auto)")
    parser.add_argument("--base-model", help="Optional base model override")
    parser.add_argument("--max-seq-length", type=int, help="Optional max sequence length override")
    parser.add_argument("--max-steps", type=int, help="Optional cap on training steps for smoke runs")
    parser.add_argument("--dry-run", action="store_true", help="Show configuration without training")
    
    args = parser.parse_args()
    
    if args.list:
        list_projects()
        return

    if args.preflight:
        print_preflight()
        return
    
    if not args.project or not args.task:
        parser.print_help()
        print("\n[ERROR] --project and --task are required (or use --list)")
        return
    
    result = train_model(
        project=args.project,
        task=args.task,
        version=args.version,
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.learning_rate,
        lora_r=args.lora_r,
        engine=args.engine,
        base_model_override=args.base_model,
        max_seq_length_override=args.max_seq_length,
        max_steps_override=args.max_steps,
        dry_run=args.dry_run,
    )
    
    if result["status"] == "error":
        sys.exit(1)


if __name__ == "__main__":
    main()
