"""Test automation multi-agent team for assessment and build planning."""

from __future__ import annotations

import os
from dataclasses import dataclass

from agents.autonomous.team_types import TeamOutput


@dataclass
class AutomationTeamRequest:
    """Request payload for test automation team execution."""

    objective: str
    app_stack: str = "unknown"
    test_framework: str = "playwright"
    scope: str = "smoke + regression"


class TestAutomationTeam:
    """Agent team focused on testability assessment and test plan generation."""

    name = "test-automation-team"

    def run(self, request: AutomationTeamRequest, dry_run: bool = True) -> TeamOutput:
        """Execute team workflow in dry-run or LLM mode."""
        if dry_run:
            return self._dry_run(request)
        return self._llm_mode(request)

    def _dry_run(self, request: AutomationTeamRequest) -> TeamOutput:
        return TeamOutput(
            team=self.name,
            mode="dry-run",
            summary=(
                "Prepared a risk-tiered automation plan with assessment, build order, and "
                "flake-mitigation checkpoints."
            ),
            actions=[
                f"Assess testability for objective: {request.objective}",
                "Inventory existing tests and map gaps by user-critical flows.",
                "Generate P0 smoke suite first, then high-value regression suite.",
                "Define explicit assertions per flow (UI state, API contract, and navigation outcomes).",
                "Create Playwright specs with stable selectors and deterministic waits.",
                "Run flaky-test triage and add stabilization fixes before expansion.",
            ],
            artifacts=[
                "testability-assessment.md",
                "test-plan-priority-matrix.md",
                "playwright-suite-seed.spec.ts",
                "failure-triage-checklist.md",
            ],
            metrics={
                "target_first_run_pass_rate": 0.75,
                "target_flake_rate_max": 0.05,
                "target_generation_acceptance_rate": 0.7,
            },
            notes=[
                f"App stack hint: {request.app_stack}",
                f"Framework: {request.test_framework}",
                f"Scope: {request.scope}",
            ],
        )

    def _llm_mode(self, request: AutomationTeamRequest) -> TeamOutput:
        """Run CrewAI-backed flow when available; otherwise fallback to dry-run."""
        try:
            from crewai import Agent, Crew, LLM, Process, Task
        except ImportError:
            fallback = self._dry_run(request)
            fallback.mode = "fallback-dry-run"
            fallback.notes.append("CrewAI unavailable; returned dry-run output.")
            return fallback

        llm = LLM(
            model="specpilot-local",
            base_url="http://localhost:4000",
            api_key=os.getenv("LITELLM_MASTER_KEY", "sk-shrike-local"),
        )

        assessor = Agent(
            role="Testability Assessor",
            goal="Score testability and identify blockers for reliable automation.",
            backstory="You evaluate selectors, stability risks, and observability gaps.",
            llm=llm,
            verbose=False,
        )
        planner = Agent(
            role="Coverage Planner",
            goal="Produce risk-tiered rollout plan for smoke and regression coverage.",
            backstory="You prioritize user-critical flows and minimize wasted effort.",
            llm=llm,
            verbose=False,
        )
        builder = Agent(
            role="Playwright Builder",
            goal="Generate maintainable Playwright test scaffolds and assertions.",
            backstory="You write robust tests with deterministic synchronization.",
            llm=llm,
            verbose=False,
        )

        assess_task = Task(
            description=(
                "Assess testability for this objective and list key blockers: "
                f"{request.objective}. Stack: {request.app_stack}."
            ),
            expected_output="Short markdown risk assessment with blocker list.",
            agent=assessor,
        )
        plan_task = Task(
            description=(
                "Create an ordered smoke->regression automation plan with rationale. "
                f"Scope: {request.scope}. Include explicit assertions for each critical flow."
            ),
            expected_output="Ordered plan with milestone checklist.",
            agent=planner,
            context=[assess_task],
        )
        build_task = Task(
            description=(
                "Generate starter Playwright test skeletons for top-priority flows "
                "with selectors and assertions."
            ),
            expected_output="Code-focused markdown with sample spec blocks.",
            agent=builder,
            context=[plan_task],
        )

        crew = Crew(
            agents=[assessor, planner, builder],
            tasks=[assess_task, plan_task, build_task],
            process=Process.sequential,
            verbose=False,
        )
        try:
            result = str(crew.kickoff())
        except Exception as exc:
            fallback = self._dry_run(request)
            fallback.mode = "fallback-dry-run"
            fallback.notes.append(f"CrewAI execution failed; returned dry-run output. Error: {exc}")
            return fallback

        return TeamOutput(
            team=self.name,
            mode="llm",
            summary="Executed test automation team flow with local LLM routing.",
            actions=["Review generated result and split into implementation tickets."],
            artifacts=["llm-team-output.md"],
            metrics={"generated_chars": len(result)},
            notes=[result[:1500]],
        )
