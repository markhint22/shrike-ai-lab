from __future__ import annotations

"""
SpecPilot Fine-tuning Script
============================
Fine-tune CodeLlama for UI test automation using QLoRA.
Optimized for RTX 2080 (8GB) / RTX 2080 Ti (11GB) with 64GB RAM.

Usage:
    python finetune.py --data data/selector_optimization.jsonl
    python finetune.py --data data/all_training.jsonl --epochs 3

Requirements:
    pip install unsloth transformers datasets peft accelerate bitsandbytes
"""

import argparse
import json
import os
from pathlib import Path
from typing import Any

try:
    from datasets import Dataset
except ImportError:
    Dataset = Any

# Check for required packages
try:
    from unsloth import FastLanguageModel
    from transformers import TrainingArguments
    from trl import SFTTrainer
    UNSLOTH_AVAILABLE = True
except ImportError:
    UNSLOTH_AVAILABLE = False


def load_training_data(data_path: str, task: str | None = None) -> Dataset:
    """Load JSONL training data and convert to instruction format."""
    examples = []
    
    with open(data_path, 'r') as f:
        for line in f:
            item = json.loads(line.strip())
            
            # Convert to instruction format based on data type
            if 'bad_selector' in item and 'good_selector' in item:
                # Selector optimization
                text = f"""### Instruction:
Given this HTML element, suggest the most reliable CSS selector.

### Input:
{item.get('html', '')}
Current selector (unreliable): {item.get('bad_selector', '')}

### Response:
Better selector: {item.get('good_selector', '')}
Reason: {item.get('reason', 'More stable selector pattern')}"""

            elif 'instruction' in item and 'playwright_code' in item:
                # Test generation
                text = f"""### Instruction:
Convert this test step to Playwright code.

### Input:
{item['instruction']}

### Response:
{item['playwright_code']}"""

            elif 'error' in item and 'diagnosis' in item:
                # Failure analysis
                text = f"""### Instruction:
Analyze this test failure and suggest a fix.

### Input:
Error: {item['error']}
Selector: {item.get('selector', 'N/A')}

### Response:
Diagnosis: {item['diagnosis']}
Fix: {item.get('fix', 'See diagnosis above')}"""

            else:
                # Generic instruction format
                text = f"""### Instruction:
{item.get('instruction', 'Analyze the following')}

### Input:
{item.get('input', '')}

### Response:
{item.get('output', item.get('response', ''))}"""

            examples.append({"text": text})
    
    return Dataset.from_list(examples)


def finetune(
    data_path: str,
    model_name: str = "codellama/CodeLlama-7b-Instruct-hf",
    output_dir: str = "checkpoints",
    epochs: int = 1,
    batch_size: int = 2,
    max_seq_length: int = 2048,
    learning_rate: float = 2e-4,
):
    """Fine-tune model using QLoRA for memory efficiency."""
    
    if not UNSLOTH_AVAILABLE:
        raise ImportError("Install unsloth: pip install unsloth")
    
    print(f"🚀 Starting fine-tuning")
    print(f"   Model: {model_name}")
    print(f"   Data: {data_path}")
    print(f"   Output: {output_dir}")
    print()
    
    # Load model with 4-bit quantization (fits in 8GB VRAM)
    print("📦 Loading model with 4-bit quantization...")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=model_name,
        max_seq_length=max_seq_length,
        dtype=None,  # Auto-detect
        load_in_4bit=True,  # Critical for RTX 2080
    )
    
    # Add LoRA adapters
    print("🔧 Adding LoRA adapters...")
    model = FastLanguageModel.get_peft_model(
        model,
        r=16,  # LoRA rank
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                       "gate_proj", "up_proj", "down_proj"],
        lora_alpha=16,
        lora_dropout=0,
        bias="none",
        use_gradient_checkpointing=True,  # Saves VRAM
        random_state=42,
    )
    
    # Load training data
    print(f"📊 Loading training data from {data_path}...")
    dataset = load_training_data(data_path)
    print(f"   Loaded {len(dataset)} examples")
    
    # Training arguments optimized for RTX 2080
    training_args = TrainingArguments(
        output_dir=output_dir,
        num_train_epochs=epochs,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=4,  # Effective batch size = 8
        learning_rate=learning_rate,
        fp16=True,  # Use FP16 for RTX 2080
        logging_steps=10,
        save_steps=100,
        save_total_limit=2,
        warmup_ratio=0.03,
        lr_scheduler_type="cosine",
        optim="adamw_8bit",  # Memory-efficient optimizer
    )
    
    # Create trainer
    print("🏋️ Starting training...")
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=max_seq_length,
        args=training_args,
    )
    
    # Train
    trainer.train()
    
    # Save
    print(f"💾 Saving to {output_dir}/final...")
    model.save_pretrained(f"{output_dir}/final")
    tokenizer.save_pretrained(f"{output_dir}/final")
    
    print()
    print("✅ Fine-tuning complete!")
    print(f"   Model saved to: {output_dir}/final")
    print()
    print("Next steps:")
    print("   1. Export to Ollama: python export_to_ollama.py")
    print("   2. Test: ollama run specpilot-finetuned")


def main():
    parser = argparse.ArgumentParser(description="Fine-tune LLM for SpecPilot")
    parser.add_argument("--data", required=True, help="Path to training data (JSONL)")
    parser.add_argument("--model", default="codellama/CodeLlama-7b-Instruct-hf",
                       help="Base model to fine-tune")
    parser.add_argument("--output", default="checkpoints", help="Output directory")
    parser.add_argument("--epochs", type=int, default=1, help="Number of epochs")
    parser.add_argument("--batch-size", type=int, default=2, help="Batch size")
    parser.add_argument("--max-length", type=int, default=2048, help="Max sequence length")
    parser.add_argument("--lr", type=float, default=2e-4, help="Learning rate")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.data):
        print(f"❌ Data file not found: {args.data}")
        print()
        print("Create training data first. Example format (JSONL):")
        print('{"html": "<button>Submit</button>", "bad_selector": ".btn", "good_selector": "button:has-text(\'Submit\')", "reason": "Text is more stable"}')
        return
    
    finetune(
        data_path=args.data,
        model_name=args.model,
        output_dir=args.output,
        epochs=args.epochs,
        batch_size=args.batch_size,
        max_seq_length=args.max_length,
        learning_rate=args.lr,
    )


if __name__ == "__main__":
    main()
