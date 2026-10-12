#!/bin/bash
# Explicit local maintainer operation; CI never fetches backend code.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# != 2 || "$1" != --backend-path ]]; then
  echo 'Usage: update-session-contract-snapshots.sh --backend-path <clean committed checkout>' >&2
  exit 2
fi
backend_path="$(cd "$2" && pwd)"
if [[ -n "$(git -C "$backend_path" status --porcelain)" ]]; then
  echo 'Commit the reviewed backend contract changes before copying snapshots.' >&2
  exit 1
fi
python3 - "$backend_path" <<'PYTHON'
import hashlib,json,pathlib,shutil,subprocess,sys
backend=pathlib.Path(sys.argv[1]);root=pathlib.Path('PumpSyncTests')
p=root/'session-contract-manifest.json';m=json.loads(p.read_text())
m['revision']=subprocess.check_output(['git','-C',str(backend),'rev-parse','HEAD'],text=True).strip()
m['snapshotVersion']=1;m['checksums']={}
for mode in ['hosted','selfHosted']:
    target=root/'SessionContractSnapshots'/(mode+'.json')
    shutil.copy2(backend/'tests/PumpSync.Tests/Contracts/SessionContractV1'/(mode+'.json'),target)
    m['checksums'][mode]=hashlib.sha256(target.read_bytes()).hexdigest()
p.write_text(json.dumps(m,indent=2)+'\n')
PYTHON
bash scripts/ios/prepare-session-contract.sh
echo 'Review and commit the frontend snapshots and manifest.'
