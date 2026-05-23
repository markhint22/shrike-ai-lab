"""
Universal Code Review Agent

A multi-agent system for automated PR reviews across all Shrike Labs repos.
Uses CrewAI for orchestration and local models for analysis.
"""

from crewai import Agent, Task, Crew, LLM
from typing import List, Dict, Optional
import json


class CodeReviewCrew:
    """Multi-agent code review system."""
    
    def __init__(self, llm_base_url: str = "http://localhost:11434"):
        # Initialize models
        self.security_llm = LLM(
            model="ollama/codellama:7b",
            base_url=llm_base_url,
        )
        self.style_llm = LLM(
            model="ollama/codellama:7b",
            base_url=llm_base_url,
        )
        self.perf_llm = LLM(
            model="ollama/mistral:7b",
            base_url=llm_base_url,
        )
        
        self._setup_agents()
    
    def _setup_agents(self):
        """Create specialized review agents."""
        
        self.security_agent = Agent(
            role="Security Analyst",
            goal="Identify security vulnerabilities in code",
            backstory="""You are a security expert who reviews code for vulnerabilities.
            You look for SQL injection, XSS, auth bypasses, secrets in code, and other risks.""",
            llm=self.security_llm,
            verbose=True,
        )
        
        self.style_agent = Agent(
            role="Code Style Reviewer",
            goal="Ensure code follows best practices and conventions",
            backstory="""You are an experienced developer who reviews code quality.
            You check for naming conventions, code organization, documentation, and maintainability.""",
            llm=self.style_llm,
            verbose=True,
        )
        
        self.performance_agent = Agent(
            role="Performance Analyst",
            goal="Identify performance issues and optimization opportunities",
            backstory="""You are a performance engineer who reviews code for efficiency.
            You look for N+1 queries, memory leaks, unnecessary computations, and bottlenecks.""",
            llm=self.perf_llm,
            verbose=True,
        )
        
        self.summary_agent = Agent(
            role="Review Coordinator",
            goal="Synthesize findings into actionable feedback",
            backstory="""You coordinate code reviews and create clear, actionable summaries.
            You prioritize issues by severity and group related findings.""",
            llm=self.style_llm,
            verbose=True,
        )
    
    def review_code(
        self,
        diff: str,
        file_path: str,
        language: str,
        context: Optional[str] = None,
    ) -> Dict:
        """Run full code review on a diff."""
        
        # Create review tasks
        security_task = Task(
            description=f"""Review this {language} code for security vulnerabilities.

File: {file_path}

```diff
{diff}
```

Look for:
- SQL injection
- XSS vulnerabilities
- Hardcoded secrets/credentials
- Authentication bypasses
- Insecure data handling

Return findings as JSON: [{{"line": N, "severity": "critical/high/medium/low", "issue": "description"}}]""",
            agent=self.security_agent,
            expected_output="JSON array of security findings",
        )
        
        style_task = Task(
            description=f"""Review this {language} code for style and best practices.

File: {file_path}

```diff
{diff}
```

Check for:
- Naming conventions
- Code organization
- Missing documentation
- Error handling
- Type hints (if applicable)

Return findings as JSON: [{{"line": N, "severity": "info/low/medium", "issue": "description"}}]""",
            agent=self.style_agent,
            expected_output="JSON array of style findings",
        )
        
        perf_task = Task(
            description=f"""Review this {language} code for performance issues.

File: {file_path}

```diff
{diff}
```

Look for:
- N+1 query patterns
- Memory inefficiencies
- Blocking operations
- Missing caching opportunities
- Unnecessary computations

Return findings as JSON: [{{"line": N, "severity": "high/medium/low", "issue": "description"}}]""",
            agent=self.performance_agent,
            expected_output="JSON array of performance findings",
        )
        
        summary_task = Task(
            description="""Combine the security, style, and performance findings into a final review.

Prioritize by severity and provide:
1. Critical issues that must be fixed
2. High-priority recommendations
3. Nice-to-have improvements

Format as markdown for GitHub PR comment.""",
            agent=self.summary_agent,
            expected_output="Markdown formatted review summary",
            context=[security_task, style_task, perf_task],
        )
        
        # Run the crew
        crew = Crew(
            agents=[
                self.security_agent,
                self.style_agent,
                self.performance_agent,
                self.summary_agent,
            ],
            tasks=[security_task, style_task, perf_task, summary_task],
            verbose=True,
        )
        
        result = crew.kickoff()
        
        return {
            "summary": result,
            "security": self._parse_findings(security_task.output),
            "style": self._parse_findings(style_task.output),
            "performance": self._parse_findings(perf_task.output),
        }
    
    def _parse_findings(self, output: str) -> List[Dict]:
        """Parse JSON findings from agent output."""
        try:
            # Try to extract JSON from output
            if "[" in output:
                start = output.index("[")
                end = output.rindex("]") + 1
                return json.loads(output[start:end])
        except (json.JSONDecodeError, ValueError):
            pass
        return []


def review_pr_diff(diff: str, files: List[Dict[str, str]]) -> str:
    """
    Review a full PR diff.
    
    Args:
        diff: Full PR diff
        files: List of {path, language, diff} for each file
    
    Returns:
        Markdown formatted review
    """
    crew = CodeReviewCrew()
    all_findings = []
    
    for file_info in files:
        result = crew.review_code(
            diff=file_info["diff"],
            file_path=file_info["path"],
            language=file_info["language"],
        )
        all_findings.append({
            "file": file_info["path"],
            **result,
        })
    
    # Generate final summary
    return _format_pr_review(all_findings)


def _format_pr_review(findings: List[Dict]) -> str:
    """Format findings as GitHub PR comment."""
    
    lines = ["## 🔍 AI Code Review\n"]
    
    # Collect critical issues
    critical = []
    high = []
    medium = []
    
    for file_findings in findings:
        file_path = file_findings["file"]
        for category in ["security", "style", "performance"]:
            for issue in file_findings.get(category, []):
                item = {"file": file_path, "category": category, **issue}
                if issue.get("severity") == "critical":
                    critical.append(item)
                elif issue.get("severity") == "high":
                    high.append(item)
                else:
                    medium.append(item)
    
    if critical:
        lines.append("### 🚨 Critical Issues (must fix)\n")
        for item in critical:
            lines.append(f"- **{item['file']}:{item.get('line', '?')}** - {item['issue']}")
        lines.append("")
    
    if high:
        lines.append("### ⚠️ High Priority\n")
        for item in high:
            lines.append(f"- **{item['file']}:{item.get('line', '?')}** - {item['issue']}")
        lines.append("")
    
    if medium:
        lines.append("### 💡 Suggestions\n")
        for item in medium[:10]:  # Limit to 10
            lines.append(f"- {item['file']}:{item.get('line', '?')} - {item['issue']}")
        lines.append("")
    
    if not critical and not high and not medium:
        lines.append("✅ No significant issues found. LGTM!\n")
    
    lines.append("\n---\n*Reviewed by Shrike AI Lab*")
    
    return "\n".join(lines)


if __name__ == "__main__":
    # Example usage
    example_diff = """
+def get_user(user_id):
+    query = f"SELECT * FROM users WHERE id = {user_id}"
+    return db.execute(query)
"""
    
    crew = CodeReviewCrew()
    result = crew.review_code(
        diff=example_diff,
        file_path="app/routes/users.py",
        language="python",
    )
    
    print("Review Result:")
    print(result["summary"])
