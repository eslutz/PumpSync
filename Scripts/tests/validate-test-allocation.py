#!/usr/bin/env python3
"""Keep exhaustive validation separate from the inexpensive Apple release gate."""
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
schemes = root / 'PumpSync.xcodeproj/xcshareddata/xcschemes'

def targets(name):
    tree = ET.parse(schemes / f'{name}.xcscheme')
    return {t.find('BuildableReference').get('BlueprintName'): t
            for t in tree.findall('./TestAction/Testables/TestableReference')}

full = targets('PumpSync')
assert set(full) == {'PumpSyncTests', 'PumpSyncUITests'}
for target in full.values():
    assert target.get('skipped') == 'NO'
    assert target.find('SelectedTests') is None
    assert target.find('SkippedTests') is None
lean = targets('PumpSync Cloud Smoke')
assert set(lean) == set(full)
assert all(t.get('skipped') == 'NO' for t in lean.values())
assert lean['PumpSyncTests'].find('SelectedTests') is None
assert lean['PumpSyncTests'].find('SkippedTests') is None
assert {t.get('Identifier') for t in lean['PumpSyncUITests'].findall('./SelectedTests/Test')} == {
    'PumpSyncUITests/testAppLaunches()',
    'PumpSyncUITests/testConnectionRecoveryOpensSettingsTab()',
}
print('Full local/GitHub coverage and lean Apple release allocation verified.')
