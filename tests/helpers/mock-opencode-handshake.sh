#!/usr/bin/env bash
# Emit EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1 when a governed runner set HANDSHAKE_PATH.
# Source or paste into mock OpenCode binaries used by regression tests.
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  cat >"$OPENCODE_GOVERNANCE_HANDSHAKE_PATH" <<EOF
{"schema":"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1","role":"$role","plugin_sha256":"mock","policy_sha256":"mock","process_id":$$,"nonce":"mock-test","started_at_utc":"1970-01-01T00:00:00Z"}
EOF
fi
