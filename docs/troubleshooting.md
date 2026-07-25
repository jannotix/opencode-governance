# Troubleshooting

## A model does not load

Run:

```bash
opencode models
```

Confirm the configured model ID exactly matches the locally registered ID. Re-run the installer to change model assignments.

## A variant is rejected

Re-run the installer and leave the variant blank, or enter a variant actually supported by the selected model.

## Commands do not appear

Restart OpenCode. Verify the global OpenCode configuration path and run the verification script.

## Existing OpenCode configuration was changed incorrectly

The installer stores timestamped backups under the OpenCode configuration directory. Restore the relevant backup, then re-run the installer.

## Workflow cannot continue

Run `/ai-status` and inspect the current `.ai/tasks/<TASK-ID>/` artifacts. A `BLOCKED` verdict should include the missing evidence or environment dependency.
