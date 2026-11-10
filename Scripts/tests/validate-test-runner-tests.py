#!/usr/bin/env python3
"""Exercise the real wrapper with isolated tools, including macOS Bash 3.2."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[2] / 'Scripts/ios/validate-tests.sh'
with tempfile.TemporaryDirectory(prefix='pumpsync-test-runner-') as temporary:
    root = Path(temporary)
    scripts = root / 'Scripts/ios'
    scripts.mkdir(parents=True)
    shutil.copyfile(source, scripts / 'validate-tests.sh')
    (scripts / 'prepare-session-contract.sh').write_text('#!/bin/bash\nexit 0\n')
    tools = root / 'bin'
    tools.mkdir()
    (tools / 'xcodegen').write_text('#!/bin/bash\nexit 0\n')
    (tools / 'xcodebuild').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path(os.environ['CAPTURE']).write_text(json.dumps(sys.argv[1:]))
print(os.environ.get('FAKE_OUTPUT', 'Tests passed'))
sys.exit(int(os.environ.get('FAKE_STATUS', '0')))
''')
    for tool in tools.iterdir():
        tool.chmod(0o755)
    base = os.environ.copy()
    for key in ['PUMPSYNC_DERIVED_DATA_PATH', 'FAKE_OUTPUT', 'FAKE_STATUS']:
        base.pop(key, None)
    base.update(PATH=f'{tools}:{base["PATH"]}', CAPTURE=str(root / 'args.json'),
                PUMPSYNC_TEST_LOG=str(root / 'test.log'),
                PUMPSYNC_TEST_DESTINATION='platform=iOS Simulator,id=fixture')
    prefix = ['test', '-project', 'PumpSync.xcodeproj', '-scheme', 'PumpSync',
              '-destination', base['PUMPSYNC_TEST_DESTINATION']]
    cases = [
        ('no optional arguments', {}, [], [], 0),
        ('empty optional path', {'PUMPSYNC_DERIVED_DATA_PATH': ''}, [], [], 0),
        ('CI CLI path', {}, ['-jobs', '1', '-derivedDataPath', '.DerivedData'],
         ['-jobs', '1', '-derivedDataPath', '.DerivedData'], 0),
        ('environment path with spaces', {'PUMPSYNC_DERIVED_DATA_PATH': '/tmp/derived data'},
         ['-resultBundlePath', '/tmp/result bundle'],
         ['-derivedDataPath', '/tmp/derived data', '-resultBundlePath', '/tmp/result bundle'], 0),
        ('test failure propagated', {'FAKE_STATUS': '65'}, [], [], 65),
        ('warnings rejected', {'FAKE_OUTPUT': 'warning: fixture'}, [], [], 1),
    ]
    for name, extra, arguments, expected, status in cases:
        result = subprocess.run(['/bin/bash', str(scripts / 'validate-tests.sh'), *arguments],
                                env={**base, **extra}, text=True, capture_output=True)
        assert result.returncode == status, (name, result.returncode, result.stdout, result.stderr)
        actual = json.loads((root / 'args.json').read_text())
        assert actual == prefix + expected, (name, actual)
        print(f'PASS: {name}')
print('Test runner regression checks passed.')
