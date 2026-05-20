# Shrike AI Lab - Year 1 Roadmap

Strategic roadmap for building AI-powered developer tools for indie developers and small teams.

## Vision

Build a suite of AI tools that give small teams the capabilities of large engineering organizations:
- **Local-first**: Run on your hardware, no recurring API costs
- **Privacy-focused**: Your code never leaves your machine
- **Open models**: No vendor lock-in

## Q3 2026 (Current - July-September)

### Month 1: Foundation (July)

- [x] Set up Ollama + LiteLLM infrastructure
- [x] Create SpecPilot training scaffold
- [x] Create GitLark training scaffold
- [x] Create BillWatch training scaffold
- [x] Build code review agent
- [ ] Deploy to Windows PC (64GB RAM, RTX 2080)
- [ ] Collect initial training data from existing repos

### Month 2: First Models (August)

- [ ] Train SpecPilot selector optimizer v1
- [ ] Train GitLark code explainer v1
- [ ] Train BillWatch bill summarizer v1
- [ ] Integrate local models into production apps
- [ ] Measure quality vs Claude baseline

### Month 3: Iteration (September)

- [ ] Collect user feedback on local model quality
- [ ] Expand training datasets (target: 10,000 examples each)
- [ ] Train v2 models with expanded data
- [ ] Add commit message generation to GitLark
- [ ] Add PR description generation to GitLark

## Q4 2026 (October-December)

### Month 4: Code Review Agent (October)

- [ ] Deploy code review agent to all repos
- [ ] GitHub Action integration
- [ ] Collect review feedback (accept/reject)
- [ ] Train custom review model on feedback

### Month 5: SpecPilot Intelligence (November)

- [ ] Train failure analyzer model
- [ ] Train test generator model
- [ ] Integrate with SpecPilot autonomy system
- [ ] Achieve 80% first-try selector success rate

### Month 6: Multi-Project Learning (December)

- [ ] Cross-project pattern learning
- [ ] Shared knowledge base across all apps
- [ ] "What works in BillWatch" → applies to GitLark
- [ ] End-of-year review and 2027 planning

## Q1 2027 (January-March)

### Themes: Scale & Polish

**GitLark AI Features**
- AI conversation agents (code-review, architecture, planning)
- Repository understanding ("What does this repo do?")
- Codebase Q&A ("Where is authentication handled?")
- Intelligent PR summaries

**SpecPilot Intelligence**
- Self-healing tests (auto-fix broken selectors)
- Test coverage suggestions
- Visual regression detection with AI
- Natural language to test conversion

**BillWatch AI Features**
- Bill comparison ("How does this differ from HR 1234?")
- Voting prediction (based on sponsor history)
- Impact analysis for constituents
- Legislative tracking alerts with context

## Q2 2027 (April-June)

### Themes: New Products

**Documentation Agent**
- Auto-generate README from code
- API documentation from routes
- Architecture diagrams from code
- Keep docs in sync with code changes

**Refactoring Agent**
- Identify code smells
- Suggest and apply refactors
- Breaking change detection
- Migration assistance

**DevOps Agent**
- Deployment health monitoring
- Auto-fix common deployment issues
- Performance regression detection
- Cost optimization suggestions

## Success Metrics

### Technical Metrics

| Metric | Current | Q4 2026 | Q2 2027 |
|--------|---------|---------|---------|
| Local model accuracy vs Claude | N/A | 80% | 90% |
| Average response latency | N/A | <2s | <1s |
| Training data volume | 100 | 10,000 | 100,000 |
| Models in production | 0 | 3 | 8 |

### Business Metrics

| Metric | Current | Q4 2026 | Q2 2027 |
|--------|---------|---------|---------|
| Claude API cost/month | ~$50 | ~$10 | ~$5 |
| User satisfaction (AI features) | N/A | 75% | 85% |
| AI feature usage rate | N/A | 50% | 70% |

### Model Quality Metrics

| Task | Baseline (Claude) | Local v1 | Local v2 |
|------|-------------------|----------|----------|
| Code explanation accuracy | 95% | 80% | 90% |
| Commit message quality | 90% | 75% | 85% |
| Bill summary readability | 95% | 80% | 90% |
| Security issue detection | 85% | 70% | 80% |

## Resource Requirements

### Hardware

**Current** (Windows PC):
- 64GB RAM
- RTX 2080 (8GB VRAM)
- Can run: 7B models, QLoRA training

**Recommended Upgrade** (for faster training):
- RTX 4090 (24GB VRAM)
- Can run: 13B models, faster training

### Compute Time Estimates

| Task | Hardware | Time |
|------|----------|------|
| 7B model inference | RTX 2080 | ~2-5s/response |
| QLoRA training (1000 examples) | RTX 2080 | ~2-4 hours |
| Full 7B fine-tune | RTX 4090 | ~8-12 hours |
| 13B model inference | RTX 4090 | ~3-8s/response |

## Risk Mitigation

### Risk: Local model quality insufficient

**Mitigation**: 
- Always keep Claude fallback
- A/B test local vs Claude
- Collect user feedback
- Iterate on training data

### Risk: Training data insufficient

**Mitigation**:
- Collect data passively from production usage
- Use synthetic data generation
- Partner with other developers for data sharing

### Risk: Hardware failure

**Mitigation**:
- Keep models backed up to cloud
- Document setup for quick recovery
- Consider cloud GPU as backup (vast.ai)

## Getting Started

1. **This week**: Get Windows PC running with Ollama
2. **Next week**: Run data collection on existing repos
3. **Month 1**: Train and evaluate first models
4. **Month 2**: Deploy to production with fallback

## Contact

**Shrike Labs LLC** - mark@shrikelabsllc.com

---

*Last updated: May 2026*
*Next review: August 2026*
