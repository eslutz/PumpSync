#!/bin/bash
# Exercise fail-closed validation in a disposable copy, without changing app sources.
set -euo pipefail
cd "$(dirname "$0")/../.."
fixture_root="$(mktemp -d /tmp/pumpsync-snapshot-validator.XXXXXX)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/Scripts/ios" "$fixture_root/PumpSyncTests"
cp Scripts/ios/prepare-session-contract.sh "$fixture_root/Scripts/ios/"
cp PumpSyncTests/session-contract-manifest.json "$fixture_root/PumpSyncTests/"
cp -R PumpSyncTests/SessionContractSnapshots "$fixture_root/PumpSyncTests/"
validator="$fixture_root/Scripts/ios/prepare-session-contract.sh"
bash "$validator"
mv "$fixture_root/PumpSyncTests/SessionContractSnapshots/hosted.json" "$fixture_root/hosted.json"
if bash "$validator" > "$fixture_root/missing.log" 2>&1; then echo 'Missing snapshot incorrectly passed' >&2; exit 1; fi
mv "$fixture_root/hosted.json" "$fixture_root/PumpSyncTests/SessionContractSnapshots/hosted.json"
printf ' ' >> "$fixture_root/PumpSyncTests/SessionContractSnapshots/hosted.json"
if bash "$validator" > "$fixture_root/checksum.log" 2>&1; then echo 'Modified snapshot incorrectly passed' >&2; exit 1; fi
python3 - "$fixture_root" <<'PYTHON'
import hashlib,json,pathlib,sys
r=pathlib.Path(sys.argv[1])/'PumpSyncTests';p=r/'SessionContractSnapshots'/'hosted.json'
d=json.loads(p.read_text());d['before']['accessToken']='unexpected-real-credential';p.write_text(json.dumps(d))
m=r/'session-contract-manifest.json';v=json.loads(m.read_text());v['checksums']['hosted']=hashlib.sha256(p.read_bytes()).hexdigest();m.write_text(json.dumps(v))
PYTHON
if bash "$validator" > "$fixture_root/credential.log" 2>&1; then echo 'Unsafe credential incorrectly passed' >&2; exit 1; fi
echo 'Snapshot validation rejects missing files, modified contents, and unsafe credentials'
