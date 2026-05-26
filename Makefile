# Shrike AI Lab - Makefile
# Common commands for development and operations

.PHONY: help setup start stop logs test train benchmark clean

# Default target
help:
	@echo "Shrike AI Lab - Available Commands"
	@echo "==================================="
	@echo ""
	@echo "Setup & Infrastructure:"
	@echo "  make setup      - Initial setup (Docker, models)"
	@echo "  make start      - Start all services"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make logs       - View service logs"
	@echo "  make status     - Check service health"
	@echo ""
	@echo "Testing:"
	@echo "  make test       - Run all tests"
	@echo "  make test-llm   - Test LLM connectivity"
	@echo "  make benchmark  - Run hardware benchmark"
	@echo ""
	@echo "Training:"
	@echo "  make train      - Run SpecPilot fine-tuning"
	@echo "  make export     - Export model to Ollama"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean      - Remove cached data"
	@echo "  make pull-models - Update Ollama models"

# ===========================================
# Setup & Infrastructure
# ===========================================

setup:
	@echo "Running initial setup..."
	chmod +x scripts/*.sh
	./scripts/setup.sh

start:
	@echo "Starting services..."
	docker-compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 5
	@make status

stop:
	@echo "Stopping services..."
	docker-compose down

restart: stop start

logs:
	docker-compose logs -f --tail=100

status:
	@echo "=== Service Health ==="
	@echo -n "Ollama:   " && curl -s http://localhost:11434/api/tags > /dev/null && echo "✅ Running" || echo "❌ Not running"
	@echo -n "LiteLLM:  " && curl -s http://localhost:4000/health > /dev/null && echo "✅ Running" || echo "❌ Not running"
	@echo -n "Open WebUI: " && curl -s http://localhost:3000 > /dev/null && echo "✅ Running" || echo "❌ Not running"

# ===========================================
# Testing
# ===========================================

test:
	@echo "Running tests..."
	python -m pytest tests/ -v --tb=short

test-llm:
	@echo "Testing LLM connectivity..."
	python tests/test_llm_connection.py

benchmark:
	@echo "Running hardware benchmark..."
	./scripts/benchmark.sh

# ===========================================
# Training (Unified Pipeline)
# ===========================================

train-list:
	@echo "Available training tasks:"
	python scripts/train.py --list

train-preflight:
	@echo "Checking training readiness..."
	python scripts/train.py --preflight

train-smoke:
	@echo "Running smoke training with tiny model..."
	python scripts/train.py \
		--project specpilot \
		--task selector_optimization \
		--engine hf \
		--base-model sshleifer/tiny-gpt2 \
		--epochs 1 \
		--batch-size 1 \
		--version smoke

train-nightly:
	@echo "Running sequential nightly training queue..."
	python scripts/train_queue.py --jobs-file training/queue/nightly_jobs.json

train-18h:
	@echo "Running sequential queue continuously for 18 hours..."
	python scripts/train_queue.py \
		--jobs-file training/queue/nightly_jobs.json \
		--continue-on-error \
		--retry-count 1 \
		--repeat \
		--stamp-version \
		--max-hours 18

train-progress:
	@echo "Showing training progress summary..."
	python scripts/train_progress.py --logs-dir training/logs --tail 20

train:
	@echo "Usage: make train-<project>-<task>"
	@echo "Examples:"
	@echo "  make train-specpilot-selector"
	@echo "  make train-gitlark-explain"
	@echo "  make train-billwatch-summary"
	@echo ""
	@echo "Or use the unified script:"
	@echo "  python scripts/train.py --project gitlark --task code_explanation"

# SpecPilot training targets
train-specpilot-selector:
	python scripts/train.py --project specpilot --task selector_optimization

train-specpilot-tests:
	python scripts/train.py --project specpilot --task test_generation

train-specpilot-analyzer:
	python scripts/train.py --project specpilot --task failure_analysis

# GitLark training targets
train-gitlark-explain:
	python scripts/train.py --project gitlark --task code_explanation

train-gitlark-commit:
	python scripts/train.py --project gitlark --task commit_message

train-gitlark-pr:
	python scripts/train.py --project gitlark --task pr_description

train-gitlark-review:
	python scripts/train.py --project gitlark --task code_review

# GitLark Phase 2 capsules
train-gitlark-repo-intel:
	python scripts/train.py --project gitlark --task repo_intelligence

train-gitlark-memdiff:
	python scripts/train.py --project gitlark --task memdiff

# BillWatch training targets
train-billwatch-summary:
	python scripts/train.py --project billwatch --task summarization

train-billwatch-classify:
	python scripts/train.py --project billwatch --task classification

# BillWatch Phase 2 capsules
train-billwatch-background:
	python scripts/train.py --project billwatch --task bill_background

train-billwatch-articles:
	python scripts/train.py --project billwatch --task article_relevance

# SpecPilot Phase 2 capsules
train-specpilot-flow:
	python scripts/train.py --project specpilot --task flow_analysis

train-specpilot-build:
	python scripts/train.py --project specpilot --task test_building

# Shared / cross-project capsules
train-shared-review:
	python scripts/train.py --project shared --task code_review

train-shared-moderation:
	python scripts/train.py --project shared --task moderation

# Legacy single-model training
train-legacy:
	@echo "Starting SpecPilot fine-tuning (legacy)..."
	cd training/specpilot && python finetune.py \
		--data data/selector_optimization.jsonl \
		--epochs 1 \
		--output ../../models/specpilot-finetuned

export:
	@echo "Exporting model to Ollama format..."
	python training/specpilot/export_to_ollama.py \
		--checkpoint models/specpilot-finetuned \
		--name specpilot-finetuned

# ===========================================
# Data Collection
# ===========================================

collect-gitlark:
	@echo "Collecting GitLark training data from local repos..."
	python scripts/data-collection/collect_gitlark_data.py \
		--repos ~/LocalProjects/billwatch ~/LocalProjects/gitlark ~/LocalProjects/iptv_apps \
		--output training/gitlark/data/

collect-billwatch:
	@echo "Collecting BillWatch training data from Congress.gov..."
	@test -n "$$CONGRESS_API_KEY" || (echo "Error: CONGRESS_API_KEY not set" && exit 1)
	python scripts/data-collection/collect_billwatch_data.py \
		--congress-api-key $$CONGRESS_API_KEY \
		--output training/billwatch/data/

# ===========================================
# Model Management
# ===========================================

pull-models:
	@echo "Pulling/updating Ollama models..."
	docker exec shrike-ollama ollama pull codellama:7b-instruct
	docker exec shrike-ollama ollama pull mistral:7b-instruct
	docker exec shrike-ollama ollama pull phi3:mini

list-models:
	@echo "Available models:"
	docker exec shrike-ollama ollama list

# ===========================================
# Maintenance
# ===========================================

clean:
	@echo "Cleaning cached data..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -rf .pytest_cache 2>/dev/null || true

clean-models:
	@echo "⚠️  This will delete all downloaded models!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] && \
		docker-compose down -v && echo "Models removed." || echo "Cancelled."

# ===========================================
# Development
# ===========================================

install-dev:
	pip install -r requirements.txt
	pip install -e .

lint:
	ruff check .
	mypy training/ --ignore-missing-imports

format:
	ruff format .
