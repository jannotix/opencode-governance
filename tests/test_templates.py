from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_templates_are_model_placeholders():
    expected = {
        "architect": "__ARCHITECT_MODEL__",
        "executor": "__EXECUTOR_MODEL__",
        "reviewer": "__REVIEWER_MODEL__",
    }
    for name, token in expected.items():
        text = (ROOT / "templates" / "agents" / f"{name}.md").read_text(encoding="utf-8")
        assert f"model: {token}" in text


def test_expected_templates_exist():
    for name in ["architect", "executor", "reviewer"]:
        assert (ROOT / "templates" / "agents" / f"{name}.md").is_file()
    for name in ["ai-plan", "ai-execute", "ai-review", "ai-workflow", "ai-status"]:
        assert (ROOT / "templates" / "commands" / f"{name}.md").is_file()


def test_only_expected_roles_are_declared():
    role_files = sorted(p.stem for p in (ROOT / "templates" / "agents").glob("*.md"))
    assert role_files == ["architect", "executor", "reviewer"]


def test_workflow_has_three_correction_cycle_limit():
    text = (ROOT / "templates" / "commands" / "ai-workflow.md").read_text(encoding="utf-8")
    assert "Maximum automatic correction cycles: 3" in text
