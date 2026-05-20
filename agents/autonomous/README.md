# Autonomous Agents Setup

This directory contains configuration for running autonomous coding agents locally.

## Available Frameworks

### 1. OpenHands (Recommended)
Open-source alternative to Devin. Runs autonomous coding tasks.

```bash
# Start OpenHands with local LLM
docker run -it \
  -e LLM_MODEL="ollama/codellama:7b-instruct" \
  -e LLM_API_BASE="http://host.docker.internal:11434" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 3001:3000 \
  ghcr.io/all-hands-ai/openhands:main
```

Access at: http://localhost:3001

### 2. CrewAI
Multi-agent orchestration framework. Define specialized agents that work together.

```bash
cd crewai
pip install -r requirements.txt
python run_crew.py "Analyze the SpecPilot codebase and suggest improvements"
```

### 3. AutoGen (Microsoft)
Multi-agent conversations with code execution.

```bash
pip install pyautogen
python autogen_example.py
```

## Using with Local LLMs

All frameworks configured to use:
- **Primary**: Local Ollama (codellama:7b-instruct)
- **Fallback**: Claude API (when local can't handle complexity)

Connection via LiteLLM proxy at `http://localhost:4000`

## Resource Usage

Running autonomous agents is resource-intensive:
- Expect 6-8GB VRAM usage
- CPU will spike during inference
- Allow 30-60 seconds per agent response

For complex tasks, consider using Claude API fallback.

## Safety

⚠️ Autonomous agents can execute code. Be careful:
- Run in isolated Docker containers
- Don't give access to production credentials
- Review proposed changes before applying
- Use sandboxed environments for testing
