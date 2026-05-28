"""GitLark memdiff efficiency team for cache-vs-refresh optimization."""

from __future__ import annotations

import os
from dataclasses import dataclass

from agents.autonomous.team_types import TeamOutput


@dataclass
class MemdiffEfficiencyRequest:
    """Request payload for memdiff efficiency team execution."""

    objective: str
    query_type: str = "mixed"
    freshness_sla_minutes: int = 30
    repo_scope: str = "gitlark"


class GitlarkMemdiffEfficiencyTeam:
    """Agent team focused on memdiff decision policy and efficiency gains."""

    name = "gitlark-memdiff-efficiency-team"

    def run(self, request: MemdiffEfficiencyRequest, dry_run: bool = True) -> TeamOutput:
        if dry_run:
            return self._dry_run(request)
        return self._llm_mode(request)

    def _dry_run(self, request: MemdiffEfficiencyRequest) -> TeamOutput:
        return TeamOutput(
            team=self.name,
            mode="dry-run",
            summary=(
                "Prepared a memdiff policy blueprint to reduce unnecessary full refreshes "
                "while protecting freshness-sensitive queries."
            ),
            actions=[
                "Classify incoming queries into structure/code/freshness-sensitive buckets.",
                "Apply cache-read by default for stable structural queries.",
                "Use selective subtree refresh for medium-risk freshness queries.",
                "Reserve full-refresh for high-risk or release-sensitive requests.",
                "Enforce guardrails: max staleness budget, refresh escalation rules, and rollback triggers.",
                "Track decision outcomes and update policy thresholds weekly.",
            ],
            artifacts=[
                "memdiff-decision-rubric.md",
                "query-to-scope-mapping.json",
                "memdiff-efficiency-scorecard.md",
                "policy-thresholds.yaml",
            ],
            metrics={
                "target_cache_hit_ratio_min": 0.65,
                "target_freshness_miss_rate_max": 0.08,
                "target_latency_reduction_pct": 25,
            },
            notes=[
                f"Objective: {request.objective}",
                f"Query type: {request.query_type}",
                f"Freshness SLA (minutes): {request.freshness_sla_minutes}",
                f"Repo scope: {request.repo_scope}",
            ],
        )

    def _llm_mode(self, request: MemdiffEfficiencyRequest) -> TeamOutput:
        try:
            from crewai import Agent, Crew, LLM, Process, Task
        except ImportError:
            fallback = self._dry_run(request)
            fallback.mode = "fallback-dry-run"
            fallback.notes.append("CrewAI unavailable; returned dry-run output.")
            return fallback

        llm = LLM(
            model="mistral-local",
            base_url="http://localhost:4000",
            api_key=os.getenv("LITELLM_MASTER_KEY", "sk-shrike-local"),
        )

        assessor = Agent(
            role="Memdiff Context Assessor",
            goal="Classify query freshness risk and retrieval scope needs.",
            backstory="You determine when cache is safe and when refresh is mandatory.",
            llm=llm,
            verbose=False,
        )
        planner = Agent(
            role="Memdiff Policy Planner",
            goal="Design cache-vs-refresh policy with clear thresholds.",
            backstory="You optimize for quality, latency, and token efficiency.",
            llm=llm,
            verbose=False,
        )
        reviewer = Agent(
            role="Efficiency Reviewer",
            goal="Audit policy for edge cases, stale risks, and rollout safety.",
            backstory="You stress-test policy decisions before production rollout.",
            llm=llm,
            verbose=False,
        )

        assess_task = Task(
            description=(
                "Assess memdiff inefficiency risks for objective: "
                f"{request.objective}. Query type: {request.query_type}."
            ),
            expected_output="Risk notes and classification rubric draft.",
            agent=assessor,
        )
        plan_task = Task(
            description=(
                "Produce a concrete decision policy with thresholds for cache-read, "
                "selective refresh, and full refresh."
            ),
            expected_output="Policy table + rollout checklist.",
            agent=planner,
            context=[assess_task],
        )
        review_task = Task(
            description=(
                "Review policy for false-cache and over-refresh failure modes and "
                "propose guardrails."
            ),
            expected_output="Validation report with pass/fail gates.",
            agent=reviewer,
            context=[plan_task],
        )

        crew = Crew(
            agents=[assessor, planner, reviewer],
            tasks=[assess_task, plan_task, review_task],
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
            summary="Executed memdiff efficiency team flow with local LLM routing.",
            actions=["Review generated policy and attach to GitLark rollout checklist."],
            artifacts=["llm-memdiff-policy-output.md"],
            metrics={"generated_chars": len(result)},
            notes=[result[:1500]],
        )
