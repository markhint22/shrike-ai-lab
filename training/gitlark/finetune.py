"""
GitLark Model Fine-tuning Script

Fine-tunes CodeLlama or Mistral for code understanding tasks:
- Code explanation
- PR description generation
- Code review
- Commit message generation
"""

import os
import json
import argparse
from pathlib import Path

# Training configuration per task
TASK_CONFIGS = {
    "code_explanation": {
        "system_prompt": "You are a senior software engineer. Explain the following code clearly and concisely.",
        "input_template": "Explain this {language} code:\n\n```{language}\n{code}\n```",
        "output_field": "explanation",
        "lora_r": 16,
        "learning_rate": 2e-4,
    },
    "pr_description": {
        "system_prompt": "You are a developer writing clear PR descriptions. Given a diff, write a title and description.",
        "input_template": "Write a PR title and description for this diff:\n\n```diff\n{diff}\n```",
        "output_template": "Title: {title}\n\n{description}",
        "lora_r": 16,
        "learning_rate": 2e-4,
    },
    "code_review": {
        "system_prompt": "You are a code reviewer. Identify issues in the code and suggest improvements.",
        "input_template": "Review this code for issues:\n\n```\n{code}\n```",
        "output_field": "issues",
        "lora_r": 32,  # Higher rank for complex task
        "learning_rate": 1e-4,
    },
    "commit_message": {
        "system_prompt": "You are a developer writing conventional commit messages. Given a diff, write a semantic commit message.",
        "input_template": "Write a commit message for this diff:\n\n```diff\n{diff}\n```",
        "output_field": "commit_message",
        "lora_r": 8,  # Lower rank for simpler task
        "learning_rate": 3e-4,
    },
}


def load_training_data(data_path: str, task: str) -> list:
    """Load and format training data for the specified task."""
    config = TASK_CONFIGS[task]
    examples = []
    
    with open(data_path, 'r') as f:
        for line in f:
            item = json.loads(line)
            
            # Format input
            input_text = config["input_template"].format(**item)
            
            # Format output
            if "output_template" in config:
                output_text = config["output_template"].format(**item)
            else:
                output_field = config["output_field"]
                output_text = item[output_field]
                if isinstance(output_text, list):
                    output_text = json.dumps(output_text, indent=2)
            
            examples.append({
                "instruction": config["system_prompt"],
                "input": input_text,
                "output": output_text,
            })
    
    return examples


def prepare_dataset(examples: list):
    """Convert examples to HuggingFace dataset format."""
    try:
        from datasets import Dataset
    except ImportError:
        print("Install datasets: pip install datasets")
        return None
    
    return Dataset.from_list(examples)


def finetune(
    data_path: str,
    task: str,
    output_dir: str,
    base_model: str = "codellama/CodeLlama-7b-hf",
    epochs: int = 3,
    batch_size: int = 4,
):
    """Fine-tune model using QLoRA."""
    try:
        from unsloth import FastLanguageModel
        from trl import SFTTrainer
        from transformers import TrainingArguments
    except ImportError:
        print("Install dependencies:")
        print("  pip install unsloth trl transformers")
        return
    
    config = TASK_CONFIGS[task]
    
    print(f"Loading base model: {base_model}")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=base_model,
        max_seq_length=2048,
        dtype=None,  # Auto-detect
        load_in_4bit=True,  # QLoRA
    )
    
    # Add LoRA adapters
    model = FastLanguageModel.get_peft_model(
        model,
        r=config["lora_r"],
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                       "gate_proj", "up_proj", "down_proj"],
        lora_alpha=16,
        lora_dropout=0.05,
        bias="none",
        use_gradient_checkpointing=True,
    )
    
    # Load and prepare data
    print(f"Loading training data from {data_path}")
    examples = load_training_data(data_path, task)
    dataset = prepare_dataset(examples)
    
    if dataset is None:
        return
    
    # Format for training
    def formatting_prompts_func(examples):
        texts = []
        for instruction, input_text, output in zip(
            examples["instruction"],
            examples["input"],
            examples["output"]
        ):
            text = f"""### Instruction:
{instruction}

### Input:
{input_text}

### Response:
{output}"""
            texts.append(text)
        return {"text": texts}
    
    dataset = dataset.map(formatting_prompts_func, batched=True)
    
    # Training arguments
    training_args = TrainingArguments(
        output_dir=output_dir,
        num_train_epochs=epochs,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=4,
        warmup_steps=10,
        learning_rate=config["learning_rate"],
        fp16=True,
        logging_steps=10,
        save_strategy="epoch",
        optim="adamw_8bit",
    )
    
    # Create trainer
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=2048,
        args=training_args,
    )
    
    # Train
    print(f"Starting training for {epochs} epochs...")
    trainer.train()
    
    # Save
    print(f"Saving model to {output_dir}")
    model.save_pretrained(output_dir)
    tokenizer.save_pretrained(output_dir)
    
    print("Training complete!")
    print(f"Export to Ollama: python export_to_ollama.py --model {output_dir} --name gitlark-{task}")


def main():
    parser = argparse.ArgumentParser(description="Fine-tune GitLark models")
    parser.add_argument("--data", required=True, help="Path to training data JSONL")
    parser.add_argument("--task", required=True, choices=list(TASK_CONFIGS.keys()),
                       help="Training task")
    parser.add_argument("--output", required=True, help="Output directory for model")
    parser.add_argument("--base-model", default="codellama/CodeLlama-7b-hf",
                       help="Base model to fine-tune")
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs")
    parser.add_argument("--batch-size", type=int, default=4, help="Batch size")
    
    args = parser.parse_args()
    
    finetune(
        data_path=args.data,
        task=args.task,
        output_dir=args.output,
        base_model=args.base_model,
        epochs=args.epochs,
        batch_size=args.batch_size,
    )


if __name__ == "__main__":
    main()
