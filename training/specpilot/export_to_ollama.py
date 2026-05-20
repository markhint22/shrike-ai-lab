"""
Export Fine-tuned Model to Ollama
=================================
Converts a fine-tuned model checkpoint to Ollama format.

Usage:
    python export_to_ollama.py --checkpoint checkpoints/final --name specpilot-finetuned

This creates a Modelfile and imports the model into Ollama.
"""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path


def create_modelfile(base_model: str, adapter_path: str, output_path: str) -> str:
    """Create an Ollama Modelfile for the fine-tuned model."""
    
    modelfile_content = f"""# SpecPilot Fine-tuned Model
# Base: {base_model}
# Adapter: {adapter_path}

FROM {base_model}

# Set model parameters optimized for code generation
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER num_ctx 4096

# System prompt for selector optimization
SYSTEM \"\"\"You are an expert in web automation and UI testing. You specialize in:
1. Finding reliable CSS and XPath selectors
2. Writing Playwright test code
3. Diagnosing test failures

Always prefer stable selectors like data-testid attributes over fragile class names.
Be concise and provide working code.\"\"\"

# Include the fine-tuned adapter
ADAPTER {adapter_path}
"""
    
    with open(output_path, 'w') as f:
        f.write(modelfile_content)
    
    return output_path


def export_to_gguf(checkpoint_path: str, output_path: str) -> str:
    """Convert HuggingFace checkpoint to GGUF format for Ollama."""
    
    # This requires llama.cpp's convert script
    # For now, we'll use the simpler approach of just using the adapter
    
    print(f"⚠️  Full GGUF export requires llama.cpp")
    print(f"   For now, using adapter approach")
    
    # Check if the checkpoint has adapter files
    checkpoint = Path(checkpoint_path)
    adapter_files = list(checkpoint.glob("adapter_*.safetensors")) + \
                   list(checkpoint.glob("adapter_*.bin"))
    
    if adapter_files:
        print(f"   Found adapter files: {[f.name for f in adapter_files]}")
        return str(adapter_files[0])
    else:
        print(f"   No adapter files found in {checkpoint_path}")
        return None


def import_to_ollama(modelfile_path: str, model_name: str):
    """Import model into Ollama using the Modelfile."""
    
    print(f"Importing {model_name} into Ollama...")
    
    try:
        result = subprocess.run(
            ["ollama", "create", model_name, "-f", modelfile_path],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print(f"✅ Model '{model_name}' imported successfully")
            print(f"   Test with: ollama run {model_name}")
        else:
            print(f"❌ Import failed: {result.stderr}")
            
    except FileNotFoundError:
        print("❌ 'ollama' command not found")
        print("   If using Docker, run:")
        print(f"   docker exec shrike-ollama ollama create {model_name} -f /path/to/Modelfile")


def main():
    parser = argparse.ArgumentParser(description="Export fine-tuned model to Ollama")
    parser.add_argument("--checkpoint", required=True, help="Path to fine-tuned checkpoint")
    parser.add_argument("--name", default="specpilot-finetuned", help="Model name in Ollama")
    parser.add_argument("--base-model", default="codellama:7b-instruct", 
                       help="Base model to apply adapter to")
    parser.add_argument("--output-dir", default=".", help="Output directory for Modelfile")
    
    args = parser.parse_args()
    
    checkpoint_path = Path(args.checkpoint)
    if not checkpoint_path.exists():
        print(f"❌ Checkpoint not found: {checkpoint_path}")
        print()
        print("Run fine-tuning first:")
        print("  cd training/specpilot")
        print("  python finetune.py --data data/selector_optimization.jsonl")
        return
    
    print(f"Exporting model from: {checkpoint_path}")
    print(f"Base model: {args.base_model}")
    print(f"Output name: {args.name}")
    print()
    
    # Step 1: Find/convert adapter
    adapter_path = export_to_gguf(str(checkpoint_path), args.output_dir)
    
    if not adapter_path:
        print()
        print("Alternative: Use base model with custom system prompt")
        print("Update configs/litellm_config.yaml to add system prompt")
        return
    
    # Step 2: Create Modelfile
    modelfile_path = Path(args.output_dir) / f"Modelfile.{args.name}"
    create_modelfile(args.base_model, adapter_path, str(modelfile_path))
    print(f"Created Modelfile: {modelfile_path}")
    
    # Step 3: Import to Ollama
    print()
    import_to_ollama(str(modelfile_path), args.name)
    
    print()
    print("=" * 50)
    print("Next steps:")
    print("=" * 50)
    print(f"1. Test the model:")
    print(f"   ollama run {args.name}")
    print()
    print(f"2. Update LiteLLM config to use the new model:")
    print(f"   Edit configs/litellm_config.yaml:")
    print(f"   - model_name: specpilot-finetuned")
    print(f"     litellm_params:")
    print(f"       model: ollama/{args.name}")
    print()
    print(f"3. Restart LiteLLM:")
    print(f"   docker-compose restart litellm")


if __name__ == "__main__":
    main()
