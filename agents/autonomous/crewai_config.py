"""
CrewAI Configuration for Shrike Labs
=====================================
Multi-agent setup for various development tasks.

Usage:
    python run_crew.py "Your task description"
    python run_crew.py --crew specpilot "Analyze test failures"

Available Crews:
    - default: General coding assistance
    - specpilot: UI test automation specialists
    - reviewer: Code review and refactoring
"""

import os
from crewai import Agent, Crew, Task, Process
from langchain_openai import ChatOpenAI

# Configure LLM to use local Ollama via LiteLLM
def get_local_llm():
    """Get local LLM configured via LiteLLM proxy."""
    return ChatOpenAI(
        model="specpilot-local",
        base_url="http://localhost:4000",
        api_key="sk-shrike-local",
        temperature=0.7,
    )

def get_cloud_llm():
    """Get Claude for complex reasoning tasks."""
    return ChatOpenAI(
        model="claude-fallback",
        base_url="http://localhost:4000",
        api_key="sk-shrike-local",
        temperature=0.3,
    )


# ===========================================
# SpecPilot Crew - UI Test Automation
# ===========================================

def create_specpilot_crew():
    """Create a crew specialized in UI test automation."""
    
    local_llm = get_local_llm()
    
    # Selector Expert Agent
    selector_expert = Agent(
        role="Selector Optimization Expert",
        goal="Find the most reliable and maintainable CSS/XPath selectors",
        backstory="""You are an expert in web automation with deep knowledge of 
        CSS selectors, XPath, and Playwright. You understand that good selectors
        are stable, unique, and resilient to UI changes. You prefer data-testid
        attributes, semantic HTML, and text content over fragile class names.""",
        llm=local_llm,
        verbose=True,
    )
    
    # Test Generator Agent
    test_generator = Agent(
        role="Playwright Test Generator",
        goal="Convert natural language test descriptions into working Playwright code",
        backstory="""You write clean, maintainable Playwright test code. You follow
        best practices: proper waiting strategies, error handling, and clear assertions.
        You generate TypeScript code compatible with Playwright Test framework.""",
        llm=local_llm,
        verbose=True,
    )
    
    # Failure Analyst Agent
    failure_analyst = Agent(
        role="Test Failure Analyst",
        goal="Diagnose why UI tests fail and suggest fixes",
        backstory="""You are a debugging expert who can analyze test failures from
        error messages, screenshots, and HTML snapshots. You identify root causes
        like timing issues, selector problems, and application bugs.""",
        llm=get_cloud_llm(),  # Use Claude for complex analysis
        verbose=True,
    )
    
    return {
        "selector_expert": selector_expert,
        "test_generator": test_generator,
        "failure_analyst": failure_analyst,
    }


# ===========================================
# Code Review Crew
# ===========================================

def create_review_crew():
    """Create a crew for code review and refactoring."""
    
    local_llm = get_local_llm()
    
    # Code Reviewer
    reviewer = Agent(
        role="Senior Code Reviewer",
        goal="Review code for bugs, security issues, and best practices",
        backstory="""You are a senior engineer with expertise in Python, TypeScript,
        and web development. You focus on code quality, security, and maintainability.
        You give constructive feedback with specific suggestions.""",
        llm=local_llm,
        verbose=True,
    )
    
    # Refactoring Expert
    refactorer = Agent(
        role="Refactoring Expert",
        goal="Improve code structure without changing behavior",
        backstory="""You specialize in code refactoring. You identify code smells,
        apply design patterns appropriately, and improve readability. You always
        ensure refactoring doesn't break existing functionality.""",
        llm=local_llm,
        verbose=True,
    )
    
    return {
        "reviewer": reviewer,
        "refactorer": refactorer,
    }


# ===========================================
# Main Entry Point
# ===========================================

def run_specpilot_analysis(task_description: str):
    """Run SpecPilot crew on a task."""
    
    agents = create_specpilot_crew()
    
    task = Task(
        description=task_description,
        expected_output="Detailed analysis with actionable recommendations",
        agent=agents["selector_expert"],
    )
    
    crew = Crew(
        agents=list(agents.values()),
        tasks=[task],
        process=Process.sequential,
        verbose=True,
    )
    
    return crew.kickoff()


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python crewai_config.py 'Your task description'")
        sys.exit(1)
    
    task = " ".join(sys.argv[1:])
    result = run_specpilot_analysis(task)
    print("\n" + "="*50)
    print("Result:")
    print("="*50)
    print(result)
