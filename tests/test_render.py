from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def render(path: Path, model_token: str, model: str, variant_token: str, variant: str):
    text = path.read_text(encoding="utf-8")
    text = text.replace(model_token, model)
    text = text.replace(variant_token, f"variant: {variant}" if variant else "")
    return text


def test_rendered_agents_have_models_and_no_placeholders():
    cases = [
        ("architect", "__ARCHITECT_MODEL__", "provider-a/model-x", "__ARCHITECT_VARIANT_LINE__", "deep"),
        ("executor", "__EXECUTOR_MODEL__", "provider-b/model-y", "__EXECUTOR_VARIANT_LINE__", ""),
        ("reviewer", "__REVIEWER_MODEL__", "provider-c/model-z", "__REVIEWER_VARIANT_LINE__", "strict"),
    ]
    for name, mt, model, vt, variant in cases:
        text = render(ROOT / "templates" / "agents" / f"{name}.md", mt, model, vt, variant)
        assert f"model: {model}" in text
        assert "__" not in text
        if variant:
            assert f"variant: {variant}" in text
