#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name('apply-v344.py')
lines = path.read_text(encoding='utf-8').splitlines()
start = lines.index("workflow_entry_sh = r'''")
lines[start] = 'workflow_entry_sh = r"""'
closers = [index for index in range(start + 1, len(lines)) if lines[index] == "'''"]
if len(closers) < 2:
    raise SystemExit('Expected nested and outer workflow_entry_sh closers.')
lines[closers[1]] = '"""'
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('Repaired apply-v344.py multiline quoting')
