#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="${RUNNER_TEMP:-$(mktemp -d)}"
CONFIG="$TEMP_ROOT/opencode-v334-linux"
"$ROOT_DIR/scripts/install.sh" --config-dir "$CONFIG" --routing-config "$ROOT_DIR/tests/fixtures/routing/architect-failover.valid.json"
RUNNER="$CONFIG/opencode-governance-tools/architect-attempt.sh"
MANIFEST="$CONFIG/opencode-governance-routing.json"

run_expect_changed() {
  local project="$1" mock="$2" label="$3"
  set +e
  output="$($RUNNER --project-dir "$project" --command ai-init --arguments "$label" --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" 2>&1)"
  code=$?
  set -e
  [[ $code -ne 0 ]]
  grep -q 'PROJECT_STATE_CHANGED' <<<"$output"
}

project="$TEMP_ROOT/v334-linux-dirty"
mock="$TEMP_ROOT/v334-linux-mutate-dirty"
mkdir -p "$project/.ai"
git -C "$project" init -q
git -C "$project" config user.email test@example.invalid
git -C "$project" config user.name Test
printf 'base\n' > "$project/source.txt"
git -C "$project" add source.txt
git -C "$project" commit -qm base
printf 'dirty-before\n' > "$project/source.txt"
before="$(git -C "$project" status --porcelain=v1 --untracked-files=all)"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2 ;; *) shift ;; esac; done
printf 'dirty-after\n' > "$project/source.txt"
exit 0
MOCK
chmod +x "$mock"
run_expect_changed "$project" "$mock" dirty-content-test
after="$(git -C "$project" status --porcelain=v1 --untracked-files=all)"
[[ "$before" == "$after" ]]

project="$TEMP_ROOT/v334-linux-untracked"
mock="$TEMP_ROOT/v334-linux-mutate-untracked"
mkdir -p "$project/.ai"
git -C "$project" init -q
printf 'untracked-before\n' > "$project/untracked.txt"
before="$(git -C "$project" status --porcelain=v1 --untracked-files=all)"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2 ;; *) shift ;; esac; done
printf 'untracked-after\n' > "$project/untracked.txt"
exit 0
MOCK
chmod +x "$mock"
run_expect_changed "$project" "$mock" untracked-content-test
after="$(git -C "$project" status --porcelain=v1 --untracked-files=all)"
[[ "$before" == "$after" ]]

project="$TEMP_ROOT/v334-linux-staged"
mock="$TEMP_ROOT/v334-linux-mutate-staged"
mkdir -p "$project/.ai"
git -C "$project" init -q
git -C "$project" config user.email test@example.invalid
git -C "$project" config user.name Test
printf 'base\n' > "$project/staged.txt"
git -C "$project" add staged.txt
git -C "$project" commit -qm base
printf 'staged-before\n' > "$project/staged.txt"
git -C "$project" add staged.txt
before="$(git -C "$project" status --porcelain=v1 --untracked-files=all)"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2 ;; *) shift ;; esac; done
printf 'staged-after\n' > "$project/staged.txt"
git -C "$project" add staged.txt
exit 0
MOCK
chmod +x "$mock"
run_expect_changed "$project" "$mock" staged-content-test
after="$(git -C "$project" status --porcelain=v1 --untracked-files=all)"
[[ "$before" == "$after" ]]

project="$TEMP_ROOT/v334-linux-nongit-safe"
mock="$TEMP_ROOT/v334-linux-nongit-safe-mock"
state="$TEMP_ROOT/v334-linux-nongit-safe-count"
mkdir -p "$project/.ai"
printf 'original\n' > "$project/.ai/BASELINE.md"
printf 'source\n' > "$project/source.txt"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=''; model=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2 ;; --model) model="$2"; shift 2 ;; *) shift ;; esac; done
count=0; [[ ! -f "$MOCK_STATE" ]] || count="$(cat "$MOCK_STATE")"; echo $((count+1)) > "$MOCK_STATE"
if [[ "$model" == test/architect-primary ]]; then
  printf 'partial\n' > "$project/.ai/partial.txt"
  echo 'rate limit 429' >&2
  exit 1
fi
[[ ! -e "$project/.ai/partial.txt" ]]
[[ "$(cat "$project/.ai/BASELINE.md")" == original ]]
printf 'success\n' > "$project/.ai/success.txt"
exit 0
MOCK
chmod +x "$mock"
export MOCK_STATE="$state"
"$RUNNER" --project-dir "$project" --command ai-init --arguments nongit-safe-test --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock"
[[ "$(cat "$state")" -eq 2 ]]
[[ "$(cat "$project/source.txt")" == source ]]
[[ -f "$project/.ai/success.txt" ]]

project="$TEMP_ROOT/v334-linux-nongit-mutate"
mock="$TEMP_ROOT/v334-linux-nongit-mutate-mock"
mkdir -p "$project/.ai"
printf 'source-before\n' > "$project/source.txt"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2 ;; *) shift ;; esac; done
printf 'source-after\n' > "$project/source.txt"
exit 0
MOCK
chmod +x "$mock"
run_expect_changed "$project" "$mock" nongit-mutation-test

echo 'PASS: Unix project-state integrity regressions.'
