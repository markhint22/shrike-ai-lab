"""
Documentation Agent

Automatically generates and maintains documentation from code:
- README generation
- API documentation
- Architecture diagrams
- Changelog updates
"""

from crewai import Agent, Task, Crew
from langchain.llms import Ollama
from typing import List, Dict, Optional
from pathlib import Path
import json


class DocumentationCrew:
    """Multi-agent documentation generator."""
    
    def __init__(self, llm_base_url: str = "http://localhost:11434"):
        self.llm = Ollama(
            model="mistral:7b-instruct",
            base_url=llm_base_url,
        )
        self._setup_agents()
    
    def _setup_agents(self):
        """Create specialized documentation agents."""
        
        self.analyzer = Agent(
            role="Code Analyzer",
            goal="Understand code structure and purpose",
            backstory="""You analyze codebases to understand their structure,
            dependencies, and functionality. You identify key components and patterns.""",
            llm=self.llm,
            verbose=True,
        )
        
        self.writer = Agent(
            role="Technical Writer",
            goal="Write clear, helpful documentation",
            backstory="""You are an expert technical writer who creates clear,
            comprehensive documentation. You write for developers of varying skill levels.""",
            llm=self.llm,
            verbose=True,
        )
        
        self.diagrammer = Agent(
            role="Architecture Diagrammer",
            goal="Create visual representations of code architecture",
            backstory="""You create Mermaid diagrams to visualize code architecture,
            data flows, and system interactions.""",
            llm=self.llm,
            verbose=True,
        )
    
    def generate_readme(
        self,
        repo_path: str,
        file_tree: str,
        package_json: Optional[str] = None,
        requirements_txt: Optional[str] = None,
    ) -> str:
        """Generate README.md for a repository."""
        
        context = f"""Repository structure:
```
{file_tree}
```
"""
        if package_json:
            context += f"\npackage.json:\n```json\n{package_json}\n```\n"
        if requirements_txt:
            context += f"\nrequirements.txt:\n```\n{requirements_txt}\n```\n"
        
        # Analysis task
        analyze_task = Task(
            description=f"""Analyze this repository structure and identify:
            1. Project type (web app, API, library, CLI, etc.)
            2. Main technologies used
            3. Key directories and their purposes
            4. Entry points
            
            {context}""",
            agent=self.analyzer,
            expected_output="JSON with project analysis",
        )
        
        # Writing task
        write_task = Task(
            description="""Based on the analysis, write a comprehensive README.md including:
            
            1. Project title and description
            2. Features list
            3. Tech stack
            4. Installation instructions
            5. Usage examples
            6. Project structure explanation
            7. Contributing guidelines
            8. License placeholder
            
            Use proper Markdown formatting with headers, code blocks, and lists.""",
            agent=self.writer,
            expected_output="Complete README.md content",
            context=[analyze_task],
        )
        
        # Run crew
        crew = Crew(
            agents=[self.analyzer, self.writer],
            tasks=[analyze_task, write_task],
            verbose=True,
        )
        
        result = crew.kickoff()
        return result
    
    def generate_api_docs(
        self,
        router_code: str,
        schemas_code: Optional[str] = None,
    ) -> str:
        """Generate API documentation from FastAPI/Flask code."""
        
        analyze_task = Task(
            description=f"""Analyze this API router code and extract:
            1. All endpoints (method, path, description)
            2. Request parameters (query, path, body)
            3. Response types
            4. Authentication requirements
            
            Router code:
            ```python
            {router_code}
            ```
            
            {"Schemas:" + schemas_code if schemas_code else ""}""",
            agent=self.analyzer,
            expected_output="JSON with API analysis",
        )
        
        write_task = Task(
            description="""Write API documentation in OpenAPI-style Markdown:
            
            For each endpoint:
            - Method and path
            - Description
            - Parameters table
            - Request body example
            - Response example
            - Possible errors
            
            Use code blocks for examples.""",
            agent=self.writer,
            expected_output="API documentation in Markdown",
            context=[analyze_task],
        )
        
        crew = Crew(
            agents=[self.analyzer, self.writer],
            tasks=[analyze_task, write_task],
            verbose=True,
        )
        
        return crew.kickoff()
    
    def generate_architecture_diagram(
        self,
        file_tree: str,
        description: Optional[str] = None,
    ) -> str:
        """Generate Mermaid architecture diagram."""
        
        task = Task(
            description=f"""Create a Mermaid diagram showing the architecture of this project.

File structure:
```
{file_tree}
```

{f"Description: {description}" if description else ""}

Generate a Mermaid flowchart or class diagram that shows:
- Main components
- Data flow
- Dependencies between modules

Return ONLY the Mermaid code block, starting with ```mermaid""",
            agent=self.diagrammer,
            expected_output="Mermaid diagram code",
        )
        
        crew = Crew(
            agents=[self.diagrammer],
            tasks=[task],
            verbose=True,
        )
        
        return crew.kickoff()
    
    def update_changelog(
        self,
        commits: List[Dict[str, str]],
        current_version: str,
        new_version: str,
    ) -> str:
        """Generate changelog entry from commits."""
        
        commits_text = "\n".join([
            f"- {c['hash'][:7]}: {c['message']}"
            for c in commits
        ])
        
        task = Task(
            description=f"""Generate a changelog entry for version {new_version}.

Commits since {current_version}:
{commits_text}

Format the changelog following Keep a Changelog format:
- Group by: Added, Changed, Deprecated, Removed, Fixed, Security
- Write user-friendly descriptions (not raw commit messages)
- Include breaking changes prominently

Return Markdown for the changelog entry.""",
            agent=self.writer,
            expected_output="Changelog entry in Markdown",
        )
        
        crew = Crew(
            agents=[self.writer],
            tasks=[task],
            verbose=True,
        )
        
        return crew.kickoff()


def generate_docs_for_repo(repo_path: str) -> Dict[str, str]:
    """Generate all documentation for a repository."""
    
    repo = Path(repo_path)
    crew = DocumentationCrew()
    
    # Get file tree
    def get_tree(path: Path, prefix: str = "", max_depth: int = 3, depth: int = 0) -> str:
        if depth >= max_depth:
            return ""
        
        lines = []
        items = sorted(path.iterdir(), key=lambda x: (x.is_file(), x.name))
        
        for i, item in enumerate(items):
            if item.name.startswith('.') or item.name in ['node_modules', 'venv', '__pycache__', 'dist', 'build']:
                continue
            
            is_last = i == len(items) - 1
            connector = "└── " if is_last else "├── "
            lines.append(f"{prefix}{connector}{item.name}")
            
            if item.is_dir():
                extension = "    " if is_last else "│   "
                lines.append(get_tree(item, prefix + extension, max_depth, depth + 1))
        
        return "\n".join(filter(None, lines))
    
    file_tree = get_tree(repo)
    
    # Read package files
    package_json = None
    requirements_txt = None
    
    if (repo / "package.json").exists():
        package_json = (repo / "package.json").read_text()[:2000]
    
    if (repo / "requirements.txt").exists():
        requirements_txt = (repo / "requirements.txt").read_text()
    
    # Generate docs
    results = {}
    
    results["README.md"] = crew.generate_readme(
        repo_path=str(repo),
        file_tree=file_tree,
        package_json=package_json,
        requirements_txt=requirements_txt,
    )
    
    results["ARCHITECTURE.md"] = crew.generate_architecture_diagram(
        file_tree=file_tree,
    )
    
    return results


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python documentation_agent.py <repo_path>")
        sys.exit(1)
    
    repo_path = sys.argv[1]
    docs = generate_docs_for_repo(repo_path)
    
    for filename, content in docs.items():
        print(f"\n{'='*60}")
        print(f"  {filename}")
        print(f"{'='*60}\n")
        print(content)
