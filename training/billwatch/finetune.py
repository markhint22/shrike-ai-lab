"""
BillWatch Model Fine-tuning Script

Fine-tunes Mistral or Phi-3 for bill summarization tasks:
- Plain English summaries
- Policy area classification
- Impact analysis
"""

import os
import json
import argparse
from pathlib import Path

# Training configuration per task
TASK_CONFIGS = {
    "summarization": {
        "system_prompt": "You are a policy analyst who explains legislation in plain English. Summarize the bill for a general audience.",
        "input_template": "Summarize this bill:\n\nTitle: {title}\n\n{bill_text}",
        "output_field": "summary",
        "lora_r": 16,
        "learning_rate": 2e-4,
    },
    "classification": {
        "system_prompt": "You are a policy analyst. Classify this bill into one policy area: Healthcare, Energy, Education, Defense, Economy, Immigration, Environment, Government Operations, Transportation, or Other.",
        "input_template": "Classify this bill:\n\nTitle: {title}\n\n{bill_text}",
        "output_field": "policy_area",
        "lora_r": 8,
        "learning_rate": 3e-4,
    },
    "impact": {
        "system_prompt": "You are a policy analyst. Identify who this bill affects and how.",
        "input_template": "Analyze the impact of this bill:\n\nTitle: {title}\n\n{bill_text}",
        "output_field": "impact",
        "lora_r": 16,
        "learning_rate": 2e-4,
    },
    "bill_background": {
        "system_prompt": "You are a policy analyst. Produce a full background brief for this bill.",
        "input_template": "Create a background brief for this bill:\n\nTitle: {title}\n\nText: {bill_text}\n\nTopics: {topics}",
        "output_field": "background_brief",
        "lora_r": 16,
        "learning_rate": 2e-4,
    },
    "article_relevance": {
        "system_prompt": "You are a policy research assistant. Rank and classify article relevance to a bill.",
        "input_template": "Given these bill topics and candidate articles, rank relevance.\n\nBill topics: {bill_topics}\n\nCandidate articles: {candidate_articles}",
        "output_field": "ranked_selection",
        "lora_r": 12,
        "learning_rate": 2e-4,
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
            output_field = config["output_field"]
            output_text = item[output_field]
            if isinstance(output_text, dict):
                output_text = json.dumps(output_text, indent=2)
            
            examples.append({
                "instruction": config["system_prompt"],
                "input": input_text,
                "output": output_text,
            })
    
    return examples


def finetune(
    data_path: str,
    task: str,
    output_dir: str,
    base_model: str = "mistralai/Mistral-7B-Instruct-v0.2",
    epochs: int = 3,
    batch_size: int = 2,  # Lower for longer bill texts
):
    """Fine-tune model using QLoRA."""
    try:
        from unsloth import FastLanguageModel
        from trl import SFTTrainer
        from transformers import TrainingArguments
        from datasets import Dataset
    except ImportError:
        print("Install dependencies:")
        print("  pip install unsloth trl transformers datasets")
        return
    
    config = TASK_CONFIGS[task]
    
    print(f"Loading base model: {base_model}")
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=base_model,
        max_seq_length=4096,  # Longer for bills
        dtype=None,
        load_in_4bit=True,
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
    dataset = Dataset.from_list(examples)
    
    # Format for training
    def formatting_prompts_func(examples):
        texts = []
        for instruction, input_text, output in zip(
            examples["instruction"],
            examples["input"],
            examples["output"]
        ):
            text = f"""<s>[INST] {instruction}

{input_text} [/INST] {output}</s>"""
            texts.append(text)
        return {"text": texts}
    
    dataset = dataset.map(formatting_prompts_func, batched=True)
    
    # Training arguments
    training_args = TrainingArguments(
        output_dir=output_dir,
        num_train_epochs=epochs,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=8,  # Higher for small batch
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
        max_seq_length=4096,
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


def main():
    parser = argparse.ArgumentParser(description="Fine-tune BillWatch models")
    parser.add_argument("--data", required=True, help="Path to training data JSONL")
    parser.add_argument("--task", required=True, choices=list(TASK_CONFIGS.keys()),
                       help="Training task")
    parser.add_argument("--output", required=True, help="Output directory for model")
    parser.add_argument("--base-model", default="mistralai/Mistral-7B-Instruct-v0.2",
                       help="Base model to fine-tune")
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs")
    parser.add_argument("--batch-size", type=int, default=2, help="Batch size")
    
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
