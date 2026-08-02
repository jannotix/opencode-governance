# Emit EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1 when a governed runner set HANDSHAKE_PATH.
# Dot-source from mock OpenCode PowerShell scripts used by regression tests.
if ($env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH) {
  $dir = Split-Path -Parent $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $role = if ($env:OPENCODE_GOVERNANCE_ROLE) { $env:OPENCODE_GOVERNANCE_ROLE } else { 'architect' }
  $body = [ordered]@{
    schema           = 'EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1'
    role             = $role
    plugin_sha256    = 'mock'
    policy_sha256    = 'mock'
    process_id       = $PID
    nonce            = 'mock-test'
    started_at_utc   = '1970-01-01T00:00:00Z'
  }
  ($body | ConvertTo-Json -Compress) | Set-Content -LiteralPath $env:OPENCODE_GOVERNANCE_HANDSHAKE_PATH -Encoding utf8
}
