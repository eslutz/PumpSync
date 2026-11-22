#!/usr/bin/env python3
"""Check that the local scheme runs the complete iOS XCTest suite."""
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
print('Full local iOS XCTest coverage verified.')
