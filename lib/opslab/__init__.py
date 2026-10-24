"""opslab — small, dependency-light helpers shared by the ticket seeder,
fault injectors, scenario graders and AI tooling in this repo.

Everything talks to real systems over HTTP using the standard library only,
so graders run in a bare devcontainer or CI runner without extra installs.
Configuration comes from environment variables; see lib/README.md.
"""

__all__ = ["config", "http", "servicenow", "prometheus", "dynatrace", "grading", "shell"]
