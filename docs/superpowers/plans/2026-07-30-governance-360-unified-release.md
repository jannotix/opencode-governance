# OpenCode Governance 3.6.0 Unified Release Implementation Plan

**Goal:** Convert the merged 3.6 capability overlay into one canonical OpenCode Governance 3.6.0 release with one version, one routing manifest, one installer/uninstaller path and one release-blocking verification path.

**Architecture:** Keep the five standard-library capability tools and deterministic policy projection, but move ownership into `opencode-governance-routing.json`. Canonical installers invoke one internal cross-platform capability helper after the core renderer; canonical routing verifiers validate all component fields, managed tool hashes and managed prompt sections. Canonical uninstall removes the same exact inventory before legacy-safe core cleanup.

**Constraints:** preserve providers, models, variants, fallback order, priorities, work classes, aliases, authentication, seven public agents, twelve commands and external-action boundaries. Remove the separate runtime manifest, v360 wrappers, overlay workflow and duplicate release documents.

## Tasks

1. Replace `governance-runtime-install.py` with a canonical `governance-capabilities.py` helper that merges tools, versions, hashes and prompt-section evidence into `opencode-governance-routing.json`.
2. Invoke the helper from `install.ps1` and `install.sh`; update canonical routing verification and uninstall for exactly fourteen managed tools.
3. Set `VERSION`, README and CHANGELOG to 3.6.0 and remove overlay terminology and redundant documents.
4. Move all authority, memory, evidence, staged-receipt and simulation tests into `Verify repository hardening`; remove `verify-v360.yml`.
5. Remove v360 wrappers and obsolete tests, then run all Linux and Windows workflows before merge.
