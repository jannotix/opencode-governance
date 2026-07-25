from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AGENTS = ROOT / "templates" / "agents"
COMMANDS = ROOT / "templates" / "commands"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8").lower()


def test_required_commands_exist():
    for name in (
        "ai-init.md",
        "ai-plan.md",
        "ai-execute.md",
        "ai-review.md",
        "ai-workflow.md",
        "ai-status.md",
        "ai-release.md",
    ):
        assert (COMMANDS / name).is_file(), name


def test_architect_enforces_baseline_jit_planning_and_dependency_governance():
    text = read(AGENTS / "architect.md")
    for token in (
        "codebase_baseline.md",
        "before every task",
        "ready_for_execution",
        "stable supported release",
        "license compatibility",
        "duplicate libraries",
        "deployment_scope.md",
    ):
        assert token in text, token


def test_executor_requires_ready_state_and_validated_local_commit():
    text = read(AGENTS / "executor.md")
    for token in (
        "ready_for_execution",
        "reviewer returns `pass`",
        "local task commit",
        "never use `git add .` blindly",
        "explicitly authorizes that specific push",
    ):
        assert token in text, token


def test_architect_and_reviewer_enforce_secret_handling():
    for name in ("architect.md", "reviewer.md"):
        text = read(AGENTS / name)
        assert "plaintext" in text, name
        assert "tracked secret" in text or "tracked credential" in text, name
        assert ".gitignore" in text, name


def test_modularity_prevents_both_extremes():
    architect = read(AGENTS / "architect.md")
    reviewer = read(AGENTS / "reviewer.md")
    assert "micro-file" in architect
    assert "monolithic" in reviewer
    assert "micro-file" in reviewer


def test_release_gate_requires_clean_artifact_and_production_verdict():
    text = read(COMMANDS / "ai-release.md")
    for token in (
        "deployment_scope.md",
        "clean directory",
        "external integrations",
        "ready_for_production",
        "not_ready_for_production",
        ".ai/",
        "tests",
        "secrets",
    ):
        assert token in text, token


def test_no_hardcoded_model_provider_names_in_agent_templates():
    combined = "\n".join(read(path) for path in AGENTS.glob("*.md"))
    for forbidden in ("openai/", "anthropic/", "google/", "minimax/", "zhipu/", "qwen/"):
        assert forbidden not in combined, forbidden
