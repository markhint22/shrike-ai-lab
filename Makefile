# Shrike AI Lab - Makefile
# Common commands for development and operations

.PHONY: help setup start stop logs test train benchmark clean queue-status queue-jobs queue-tail queue-failures queue-pids queue-cleanup gpu-ssh gpu-status gpu-logs gpu-restart gpu-test

DOCKER_COMPOSE := $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; else echo "docker compose"; fi)

# Default target
help:
	@echo "Shrike AI Lab - Available Commands"
	@echo "==================================="
	@echo ""
	@echo "Setup & Infrastructure (local Docker - see .env.example):"
	@echo "  make setup-linux - Install Docker/NVIDIA runtime on Linux host"
	@echo "  make setup      - Initial setup (Docker, models)"
	@echo "  make start      - Start all services"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make logs       - View service logs"
	@echo "  make status     - Check service health"
	@echo ""
	@echo "Remote GPU Server (Tailscale IP - see .env for connection details):"
	@echo "  make gpu-ssh          - SSH into the GPU server"
	@echo "  make gpu-status       - Check containers, GPU usage, API health"
	@echo "  make gpu-logs [C=..]  - Tail logs (default: shrike-llama-dflash-35b)"
	@echo "  make gpu-restart [C=..] - Restart one container and wait for healthy"
	@echo "  make gpu-test [M=..]  - Send a test completion (default: qwen-dflash-35B-A3B)"
	@echo "  make gpu-stop-inference [C=..] - Stop the inference container to free the GPU (e.g. for training)"
	@echo ""
	@echo "Overnight Local-LLM Task Queue - SERVER-RESIDENT, authoritative (agents/overnight/):"
	@echo "  Runs on the GPU server via cron - works even when the Mac is off/traveling."
	@echo "  make overnight-server-run-now  - Manually trigger a run now on the server"
	@echo "  make overnight-server-status   - Show cron job + pause state + last completed run"
	@echo "  make overnight-server-report   - Print the latest morning report"
	@echo "  make overnight-server-pause    - Stop the server queue from starting further tasks"
	@echo "  make overnight-server-resume   - Clear the pause"
	@echo "  make overnight-server-deploy   - Push an updated run_overnight_server.sh to the server"
	@echo ""
	@echo "Overnight Local-LLM Task Queue - Mac-resident, MANUAL/LOCAL TESTING ONLY:"
	@echo "  Requires the Mac awake+plugged in+on the home LAN - launchd job is disabled,"
	@echo "  not scheduled. Use these only when testing from the Mac while home."
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
	@echo "Active Model Switching:"
	@echo "  make active-35b     - Activate qwen-dflash-35B-A3B (llama.cpp DFlash)"
	@echo "  make active-35b-preflight - Validate/fix dflash bind mounts before activation"
	@echo "  make active-35b-status - Check qwen-dflash-35B-A3B download and service status"
	@echo "  make active-27b     - Switch active model to qwen-dflash-27B (experimental)"
	@echo "  make active-9b      - Switch active model to qwen-dflash-9B (experimental)"
	@echo "  make active-30b     - Switch active model to qwen3-coder:30b"
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

setup-linux:
	@echo "Bootstrapping Linux host dependencies..."
	chmod +x scripts/setup-linux.sh
	./scripts/setup-linux.sh

setup:
	@echo "Running initial setup..."
	chmod +x scripts/*.sh
	./scripts/setup.sh

start:
	@echo "Starting services..."
	$(DOCKER_COMPOSE) up -d
	@echo "Waiting for services to be ready..."
	@sleep 5
	@make status

stop:
	@echo "Stopping services..."
	$(DOCKER_COMPOSE) down

restart: stop start

logs:
	$(DOCKER_COMPOSE) logs -f --tail=100

status:
	@echo "=== Service Health ==="
	@echo -n "Ollama:   " && curl -s http://localhost:11434/api/tags > /dev/null && echo "✅ Running" || echo "❌ Not running"
	@echo -n "LiteLLM:  " && curl -s -H "Authorization: Bearer $${LITELLM_MASTER_KEY:-sk-shrike-local}" http://localhost:4000/health > /dev/null && echo "✅ Running" || echo "❌ Not running"
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
# Overnight Queue - SERVER-RESIDENT (authoritative)
# ===========================================
# The Mac-resident overnight-* targets above require the Mac to be awake,
# plugged in, and on the home LAN every night - fine for local testing, but
# useless while traveling (e.g. on vacation). The real nightly automation
# lives ON the GPU server instead (cron, not launchd/pmset - the server
# never sleeps and doesn't travel). agents/overnight/tasks.json is the
# Mac-side copy for editing; agents/overnight/server_tasks.json documents
# the server's actual repo paths. Push edits to the server with
# overnight-server-deploy.

overnight-server-run-now:
	@./scripts/gpu_server_ssh.sh "~/overnight-queue/run_overnight.sh --force"

overnight-server-status:
	@echo "=== cron job ==="
	@./scripts/gpu_server_ssh.sh "crontab -l | grep overnight-queue || echo 'Not scheduled'"
	@echo ""
	@echo "=== pause state ==="
	@./scripts/gpu_server_ssh.sh "if [ -f ~/overnight-queue/state/PAUSED ]; then echo 'PAUSED (make overnight-server-resume to clear)'; else echo 'Not paused'; fi"
	@echo ""
	@echo "=== last run marker ==="
	@./scripts/gpu_server_ssh.sh "ls -t ~/overnight-queue/state/*.done 2>/dev/null | head -1 || echo 'No completed run yet'"

overnight-server-report:
	@./scripts/gpu_server_ssh.sh "LATEST=\$$(ls -t ~/overnight-queue/reports/*.md 2>/dev/null | head -1); if [ -z \"\$$LATEST\" ]; then echo 'No reports yet.'; else cat \"\$$LATEST\"; fi"

overnight-server-pause:
	@./scripts/gpu_server_ssh.sh "mkdir -p ~/overnight-queue/state && touch ~/overnight-queue/state/PAUSED"
	@echo "Paused on the server. An in-progress task still finishes. 'make overnight-server-resume' to clear."

overnight-server-resume:
	@./scripts/gpu_server_ssh.sh "rm -f ~/overnight-queue/state/PAUSED"
	@echo "Resumed on the server."

overnight-server-deploy:
	@. ./.env && scp agents/overnight/run_overnight_server.sh mhintermeister@$$GPU_SERVER_HOST:~/overnight-queue/run_overnight.sh
	@echo "Deployed run_overnight.sh. To update tasks.json, edit agents/overnight/server_tasks.json here, then:"
	@. ./.env && echo "  scp agents/overnight/server_tasks.json mhintermeister@$$GPU_SERVER_HOST:~/overnight-queue/tasks.json"
	@echo "(tasks.json isn't auto-synced since repo paths on the server differ from the Mac - review before copying.)"

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

active-35b:
	chmod +x scripts/activate-dflash-35b.sh
	./scripts/activate-dflash-35b.sh

active-35b-preflight:
	chmod +x scripts/preflight-dflash-35b.sh
	./scripts/preflight-dflash-35b.sh --fix

active-35b-status:
	chmod +x scripts/status-dflash-35b.sh
	./scripts/status-dflash-35b.sh

active-27b:
	chmod +x scripts/switch-active-model.sh
	./scripts/switch-active-model.sh qwen-dflash-27B

active-9b:
	chmod +x scripts/switch-active-model.sh
	./scripts/switch-active-model.sh qwen-dflash-9B

active-30b:
	chmod +x scripts/switch-active-model.sh
	./scripts/switch-active-model.sh qwen3-coder:30b

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
	docker exec shrike-ollama ollama pull qwen2.5-coder:32b
	docker exec shrike-ollama ollama pull qwen3-coder:30b
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
		$(DOCKER_COMPOSE) down -v && echo "Models removed." || echo "Cancelled."

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
