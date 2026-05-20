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
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional


# Project configurations
PROJECT_CONFIGS = {
    "specpilot": {
        "tasks": ["selector_optimization", "test_generation", "failure_analysis"],
        "base_model": "codellama/CodeLlama-7b-hf",
        "max_seq_length": 2048,
        "description": "Test automation agent",
    },
    "gitlark": {
        "tasks": ["code_explanation", "pr_description", "code_review", "commit_message"],
        "base_model": "codellama/CodeLlama-7b-hf",
        "max_seq_length": 2048,
        "description": "AI code workspace",
    },
    "billwatch": {
        "tasks": ["summarization", "classification", "impact"],
        "base_model": "mistralai/Mistral-7B-Instruct-v0.2",
        "max_seq_length": 4096,
        "description": "Legislation tracker",
    },
    "shared": {
        "tasks": ["code_review"],
        "base_model": "codellama/CodeLlama-7b-hf",
        "max_seq_length": 2048,
        "description": "Cross-project models",
    },
}


def get_data_path(project: str, task: str) -> Path:
    """Get path to training data for a project/task."""
    base = Path(__file__).parent.parent / "training" / project / "data"
    
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
    dry_run: bool = False,
) -> Dict[str, Any]:
    """
    Train a model for a specific project and task.
    
    Returns training metadata.
    """
    if not validate_project_task(project, task):
        return {"status": "error", "message": "Invalid project/task"}
    
    config = PROJECT_CONFIGS[project]
    data_path = get_data_path(project, task)
    output_dir = get_model_output_dir(project, task, version)
    
    num_examples = count_examples(data_path)
    
    print(f"\n{'='*60}")
    print(f"Unified Fine-tuning Pipeline")
    print(f"{'='*60}")
    print(f"Project:     {project} ({config['description']})")
    print(f"Task:        {task}")
    print(f"Version:     {version}")
    print(f"Base Model:  {config['base_model']}")
    print(f"Data:        {data_path} ({num_examples} examples)")
    print(f"Output:      {output_dir}")
    print(f"{'='*60}")
    print(f"Hyperparameters:")
    print(f"  Epochs:        {epochs}")
    print(f"  Batch Size:    {batch_size}")
    print(f"  Learning Rate: {learning_rate}")
    print(f"  LoRA Rank:     {lora_r}")
    print(f"  Max Seq Len:   {config['max_seq_length']}")
    print(f"{'='*60}\n")
    
    if dry_run:
        print("DRY RUN - Would train with above configuration")
        return {"status": "dry_run", "config": config}
    
    # Import training dependencies
    try:
        from unsloth import FastLanguageModel
        from trl import SFTTrainer
        from transformers import TrainingArguments
        from datasets import Dataset
    except ImportError as e:
        print(f"Missing dependencies: {e}")
        print("Install with: pip install unsloth trl transformers datasets")
        return {"status": "error", "message": str(e)}
    
    # Load base model
    print(f"Loading base model: {config['base_model']}...")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=config["base_model"],
        max_seq_length=config["max_seq_length"],
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
    
    # Load and format data
    print(f"Loading training data...")
    examples = []
    with open(data_path) as f:
        for line in f:
            if line.strip():
                examples.append(json.loads(line))
    
    # Project-specific formatting
    finetune_module = get_finetune_module(project)
    if finetune_module and hasattr(finetune_module, "load_training_data"):
        formatted = finetune_module.load_training_data(str(data_path), task)
    else:
        # Default formatting
        formatted = [{"text": json.dumps(e)} for e in examples]
    
    dataset = Dataset.from_list(formatted)
    
    # Training arguments
    output_dir.mkdir(parents=True, exist_ok=True)
    
    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=epochs,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=4,
        warmup_steps=10,
        learning_rate=learning_rate,
        fp16=True,
        logging_steps=10,
        save_strategy="epoch",
        optim="adamw_8bit",
    )
    
    # Train
    print(f"Starting training for {epochs} epochs...")
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=config["max_seq_length"],
        args=training_args,
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
        "base_model": config["base_model"],
        "training_examples": num_examples,
        "epochs": epochs,
        "batch_size": batch_size,
        "learning_rate": learning_rate,
        "lora_r": lora_r,
        "trained_at": datetime.now().isoformat(),
    }
    
    with open(output_dir / "training_metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)
    
    print(f"\n✅ Training complete!")
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
    except ImportError:
        return None


def list_projects():
    """List available projects and tasks."""
    print("\n📚 Available Projects and Tasks\n")
    
    for project, config in PROJECT_CONFIGS.items():
        print(f"  {project}/")
        print(f"    Description: {config['description']}")
        print(f"    Base Model:  {config['base_model']}")
        print(f"    Tasks:")
        for task in config["tasks"]:
            try:
                data_path = get_data_path(project, task)
                count = count_examples(data_path)
                status = f"✅ {count} examples"
            except FileNotFoundError:
                status = "❌ No data"
            print(f"      - {task}: {status}")
        print()


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
    parser.add_argument("--project", "-p", help="Project name (specpilot, gitlark, billwatch, shared)")
    parser.add_argument("--task", "-t", help="Task name (depends on project)")
    parser.add_argument("--version", "-v", default="v1", help="Model version (default: v1)")
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs (default: 3)")
    parser.add_argument("--batch-size", type=int, default=4, help="Batch size (default: 4)")
    parser.add_argument("--learning-rate", type=float, default=2e-4, help="Learning rate (default: 2e-4)")
    parser.add_argument("--lora-r", type=int, default=16, help="LoRA rank (default: 16)")
    parser.add_argument("--dry-run", action="store_true", help="Show configuration without training")
    
    args = parser.parse_args()
    
    if args.list:
        list_projects()
        return
    
    if not args.project or not args.task:
        parser.print_help()
        print("\n❌ --project and --task are required (or use --list)")
        return
    
    result = train_model(
        project=args.project,
        task=args.task,
        version=args.version,
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.learning_rate,
        lora_r=args.lora_r,
        dry_run=args.dry_run,
    )
    
    if result["status"] == "error":
        sys.exit(1)


if __name__ == "__main__":
    main()
