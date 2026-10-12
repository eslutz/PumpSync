#!/bin/bash
# Validate committed test-only snapshots; no network or backend checkout required.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PYTHON'
import hashlib,json,pathlib
root=pathlib.Path('PumpSyncTests')
manifest=json.loads((root/'session-contract-manifest.json').read_text())
assert manifest['snapshotVersion']==1, 'Unsupported session contract snapshot version'
for mode in ['hosted','selfHosted']:
    p=root/'SessionContractSnapshots'/(mode+'.json')
    raw=p.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==manifest['checksums'][mode], 'Contract checksum mismatch: '+mode
    data=json.loads(raw)
    for phase in ['before','after']:
        for field,prefix in [('accessToken','test-access-'),('refreshToken','test-refresh-'),('sessionFamilyId','test-family-')]:
            assert data[phase][field]==prefix+phase, 'Unexpected credential or identifier in contract snapshot'
print('Validated both committed session contract snapshots')
PYTHON
