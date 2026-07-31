# Shrike AI Lab - Makefile
# Common commands for development and operations

.PHONY: help setup start stop logs test train benchmark clean queue-status queue-jobs queue-tail queue-failures queue-pids queue-cleanup gpu-ssh gpu-status gpu-logs gpu-restart gpu-test

# Default target
help:
	@echo "Shrike AI Lab - Available Commands"
	@echo "==================================="
	@echo ""
	@echo "Setup & Infrastructure (local Docker - see .env.example):"
	@echo "  make setup      - Initial setup (Docker, models)"
	@echo "  make start      - Start all services"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make logs       - View service logs"
	@echo "  make status     - Check service health"
	@echo ""
	@echo "Remote GPU Server (192.168.68.145 - see .env for connection details):"
	@echo "  make gpu-ssh          - SSH into the GPU server"
	@echo "  make gpu-status       - Check containers, GPU usage, API health"
	@echo "  make gpu-logs [C=..]  - Tail logs (default: shrike-llama-dflash-35b)"
	@echo "  make gpu-restart [C=..] - Restart one container and wait for healthy"
	@echo "  make gpu-test [M=..]  - Send a test completion (default: qwen-dflash-35B-A3B)"
	@echo "  make gpu-stop-inference [C=..] - Stop the inference container to free the GPU (e.g. for training)"
	@echo ""
	@echo "Overnight Local-LLM Task Queue (agents/overnight/ - see its README):"
	@echo "  make overnight-install  - Install aider, load the launchd scheduled job"
	@echo "  make overnight-run-now  - Manually trigger a run now (bypasses the nightly marker)"
	@echo "  make overnight-smoke    - Check tooling + GPU server/model reachability"
	@echo "  make overnight-status   - Show launchd job + pause state + last completed run"
	@echo "  make overnight-report   - Print the latest morning report"
	@echo "  make overnight-pause    - Stop the queue from starting further tasks (e.g. while chatting)"
	@echo "  make overnight-resume   - Clear the pause"
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
	@echo "Queue Ops (reflects THIS machine's runtime/ state - use train-remote-status for the GPU server):"
	@echo "  make queue-status   - Queue summary (pid/lock, running jobs, latest cycle)"
	@echo "  make queue-jobs     - Show all jobs in nightly queue"
	@echo "  make queue-tail     - Tail latest queue launch log"
	@echo "  make queue-failures - Show recent queue failures"
	@echo "  make queue-pids     - Show queue pid and lock ownership"
	@echo "  make queue-cleanup  - Remove stale queue pid/lock files"
	@echo ""
	@echo "Remote Training on the GPU Server (training needs the RTX 3090 - see docs/ops/LOCAL_LLM_UPGRADE_PLAN.md):"
	@echo "  make train-remote-deploy       - rsync scripts/+training/ to a dedicated dir on the GPU server"
	@echo "  make train-remote-setup        - Create a venv there and install training deps + unsloth"
	@echo "  make train-remote-run P=.. T=.. [E=hf|unsloth] [V=..] - Run one training job remotely"
	@echo "  make train-remote-queue        - Start the nightly job queue remotely (detached)"
	@echo "  make train-remote-status       - Show queue status on the GPU server"
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
# Remote GPU Server
# ===========================================

gpu-ssh:
	@./scripts/gpu_server_ssh.sh

gpu-status:
	@./scripts/gpu_server_status.sh

gpu-logs:
	@./scripts/gpu_server_logs.sh $(C)

gpu-restart:
	@./scripts/gpu_server_restart.sh $(C)

gpu-test:
	@./scripts/gpu_server_test_model.sh $(M)

gpu-stop-inference:
	@./scripts/gpu_server_stop_inference.sh $(C)

# ===========================================
# Remote Training on the GPU Server
# ===========================================
# Training needs the RTX 3090, so it runs ON the server, in a dedicated
# ~/shrike-ai-lab-training dir (kept separate from the docker-compose stack
# that serves inference - see scripts/gpu_server_deploy_training.sh).

train-remote-deploy:
	@./scripts/gpu_server_deploy_training.sh

train-remote-setup:
	@./scripts/gpu_server_ssh.sh "cd ~/shrike-ai-lab-training && \
		python3 -m venv .venv && \
		. .venv/bin/activate && \
		pip install --upgrade pip && \
		pip install -r requirements.txt && \
		pip install unsloth && \
		echo 'Remote training venv ready.'"

train-remote-run:
	@ENGINE="$(E)"; if [ -z "$$ENGINE" ]; then ENGINE=unsloth; fi; \
	VERSION="$(V)"; if [ -z "$$VERSION" ]; then VERSION="manual-$$(date +%Y%m%d-%H%M%S)"; fi; \
	./scripts/gpu_server_ssh.sh "cd ~/shrike-ai-lab-training && \
		. .venv/bin/activate && \
		python scripts/train.py --project $(P) --task $(T) --engine $$ENGINE --version $$VERSION"

train-remote-queue:
	@./scripts/gpu_server_ssh.sh "cd ~/shrike-ai-lab-training && \
		. .venv/bin/activate && \
		python scripts/start_nightly_queue.py --jobs-file training/queue/nightly_jobs.json"

train-remote-status:
	@./scripts/gpu_server_ssh.sh "cd ~/shrike-ai-lab-training && \
		. .venv/bin/activate 2>/dev/null; \
		python3 scripts/queue_ops.py status"

# ===========================================
# Overnight Local-LLM Task Runner
# ===========================================

overnight-install:
	@echo "Installing aider via pipx..."
	pipx install aider-chat || pipx upgrade aider-chat
	@echo "Loading launchd job..."
	launchctl unload ~/Library/LaunchAgents/com.shrikelabs.overnight-agent.plist 2>/dev/null || true
	launchctl load ~/Library/LaunchAgents/com.shrikelabs.overnight-agent.plist
	@echo "Done. Remember to run (once, requires sudo):"
	@echo "  sudo pmset repeat wakeorpoweron MTWRFSU 23:45:00"

overnight-run-now:
	@./agents/overnight/run_overnight.sh --force

overnight-smoke:
	@./agents/overnight/smoke_test.sh

overnight-status:
	@echo "=== launchd job ==="
	@launchctl list | grep shrikelabs || echo "Not loaded"
	@echo ""
	@echo "=== pause state ==="
	@if [ -f agents/overnight/state/PAUSED ]; then echo "PAUSED (make overnight-resume to clear)"; else echo "Not paused"; fi
	@echo ""
	@echo "=== last run marker ==="
	@ls -t agents/overnight/state/*.done 2>/dev/null | head -1 || echo "No completed run yet"

overnight-report:
	@LATEST=$$(ls -t agents/overnight/reports/*.md 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then echo "No reports yet."; else cat "$$LATEST"; fi

overnight-pause:
	@mkdir -p agents/overnight/state
	@touch agents/overnight/state/PAUSED
	@echo "Paused. The queue won't start any further tasks (an in-progress task still finishes)."
	@echo "Run 'make overnight-resume' to clear."

overnight-resume:
	@rm -f agents/overnight/state/PAUSED
	@echo "Resumed. The queue will start tasks normally again."

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

queue-status:
	python3 scripts/queue_ops.py status

queue-jobs:
	python3 scripts/queue_ops.py jobs

queue-tail:
	python3 scripts/queue_ops.py tail --tail-lines 120

queue-failures:
	python3 scripts/queue_ops.py failures --recent 30

queue-pids:
	python3 scripts/queue_ops.py pids

queue-cleanup:
	python3 scripts/queue_ops.py cleanup

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
