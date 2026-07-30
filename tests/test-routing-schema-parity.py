#!/usr/bin/env python3
from __future__ import annotations
import copy,json,pathlib,subprocess,tempfile

ROOT=pathlib.Path(__file__).resolve().parents[1]
INSTALL=ROOT/'scripts/install.sh';RUNNER=ROOT/'scripts/run-governed.sh';CONTEXT=ROOT/'scripts/context-intelligence.py'
FIXTURE=ROOT/'tests/fixtures/routing/architect-failover.valid.json'

def write(path,value):path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
def fail(command,expected):
    result=subprocess.run([str(value) for value in command],text=True,capture_output=True)
    text=result.stdout+'\n'+result.stderr
    assert result.returncode!=0,(command,text)
    assert expected in text,(expected,text)
def profile():return json.loads(FIXTURE.read_text(encoding='utf-8'))

def main():
    with tempfile.TemporaryDirectory(prefix='opencode-v342-schema-') as directory:
        temp=pathlib.Path(directory);project=temp/'project';project.mkdir()
        cases=[
            ('enabled-scalar','settings.enabled_roles',lambda p:p['settings'].__setitem__('enabled_roles','architect')),
            ('eligible-scalar','settings.eligible_failures',lambda p:p['settings'].__setitem__('eligible_failures','RATE_LIMIT')),
            ('only-on-scalar','only_on must be an array',lambda p:p['roles']['architect']['primary'].__setitem__('only_on','RATE_LIMIT')),
            ('work-class-scalar','invalid work class',lambda p:p['roles']['executor']['primary'].__setitem__('work_classes','PATCH')),
            ('priority-string','positive integer',lambda p:p['roles']['reviewer']['fallbacks'][0].__setitem__('priority','1')),
            ('fallback-scalar','fallbacks must be an array',lambda p:p['roles']['reviewer'].__setitem__('fallbacks',p['roles']['reviewer']['fallbacks'][0])),
        ]
        for name,expected,mutate in cases:
            value=profile();mutate(value);path=temp/f'{name}.json';write(path,value)
            fail([INSTALL,'--config-dir',temp/f'config-{name}','--routing-config',path],expected)
        runner_cases=[
            ('runner-enabled-scalar','settings.enabled_roles',lambda p:p['settings'].__setitem__('enabled_roles','architect')),
            ('runner-eligible-scalar','unsupported eligible failure',lambda p:p['settings'].__setitem__('eligible_failures','RATE_LIMIT')),
            ('runner-cooldown-string','integer between 60 and 86400',lambda p:p['settings'].__setitem__('default_cooldown_seconds','300')),
            ('runner-only-on-scalar','only_on must be an array',lambda p:p['roles']['architect']['fallbacks'][0].__setitem__('only_on','RATE_LIMIT')),
            ('runner-priority-string','positive integer',lambda p:p['roles']['architect']['fallbacks'][0].__setitem__('priority','1')),
            ('runner-fallback-scalar','fallbacks must be an array',lambda p:p['roles']['architect'].__setitem__('fallbacks',p['roles']['architect']['fallbacks'][0])),
        ]
        for name,expected,mutate in runner_cases:
            value=profile();mutate(value);path=temp/f'{name}.json';write(path,value)
            fail([RUNNER,'--project-dir',project,'--command','ai-plan','--arguments','test','--routing-config',path,'--config-dir',temp/'runner-config','--opencode-command','definitely-not-opencode'],expected)
        print('PASS: Unix routing schema parity regressions')
if __name__=='__main__':main()
