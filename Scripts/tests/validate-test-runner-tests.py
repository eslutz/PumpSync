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
    # Run the actual selector with synthetic simctl JSON. The boot boundary
    # intentionally exits so this test can never boot or modify a simulator.
    preflight = scripts / 'validate-cloud-tests.sh'
    shutil.copyfile(source.with_name(preflight.name), preflight)
    (tools / 'xcrun').write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['SIM_CALLS'], 'a') as calls:
    print(json.dumps(args), file=calls)
if args == ['simctl', 'list', 'runtimes', 'available', '--json']:
    print(json.dumps({'runtimes': [{'identifier': os.environ['RUNTIME'], 'name': 'iOS 27.0',
                                    'isAvailable': True, 'buildversion': 'fixture'}]}))
elif args == ['simctl', 'list', 'devices', 'available', '--json']:
    print(os.environ['DEVICE_LIST'])
elif args[:2] == ['simctl', 'create']:
    print('new-device')
elif args[:2] == ['simctl', 'bootstatus']:
    sys.exit(42)
else:
    sys.exit(1)
''')
    (tools / 'xcrun').chmod(0o755)
    runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
    model = 'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation'
    stock_name = 'iPhone SE (3rd generation)'
    stock = dict(name=stock_name, udid='stock', isAvailable=True,
                 deviceTypeIdentifier=model, state='Shutdown')
    booted = {**stock, 'state': 'Booted', 'udid': 'booted-stock'}
    renamed = {**booted, 'name': 'Another name', 'udid': 'renamed'}
    for name, inventory, selected, create in [
        ('prefer booted stock simulator', [renamed, stock, booted], 'booted-stock', False),
        ('prefer stock name over renamed device', [renamed, stock], 'stock', False),
        ('reuse renamed model', [renamed], 'renamed', False),
        ('create missing model on required runtime', [{**stock, 'isAvailable': False},
                                                      {**stock, 'deviceTypeIdentifier': 'iPad'}], 'new-device', True),
    ]:
        calls_file = root / 'sim-calls.jsonl'
        calls_file.write_text('')
        inventory_by_runtime = {'devices': {runtime: inventory, 'other-runtime': [booted]}}
        env = {**base, 'FAKE_OUTPUT': 'Xcode 27.2', 'RUNTIME': runtime, 'SIM_CALLS': str(calls_file),
               'DEVICE_LIST': json.dumps(inventory_by_runtime), 'PUMPSYNC_CLOUD_RESULTS_DIR': str(root / 'results')}
        result = subprocess.run(['/bin/bash', str(preflight)], env=env, text=True, capture_output=True)
        assert result.returncode == 42, (name, result.stdout, result.stderr)
        calls = [json.loads(line) for line in calls_file.read_text().splitlines()]
        creations = [args for args in calls if args[:2] == ['simctl', 'create']]
        assert creations == ([['simctl', 'create', stock_name, model, runtime]] if create else []), (name, calls)
        assert calls[-1] == ['simctl', 'bootstatus', selected, '-b'], (name, calls)
        print(f'PASS: {name}')
print('Test runner regression checks passed.')
