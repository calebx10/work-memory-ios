#!/usr/bin/env python3
from pathlib import Path
import plistlib, re
root=Path(__file__).resolve().parents[1]
ios=root/'app/ios'
project=(ios/'WorkMemory.xcodeproj/project.pbxproj').read_text()
missing=[]
for path in re.findall(r'path = "?([^;"\n]+)"?;',project):
    if path in ('WorkMemory.app','WorkMemoryUITests.xctest'): continue
    if not (ios/path).exists(): missing.append(path)
assert not missing, f'Missing project files: {missing}'
info=plistlib.loads((ios/'WorkMemory/Info.plist').read_bytes())
assert info['UIBackgroundModes']==['audio']
assert 'NSMicrophoneUsageDescription' in info
assert 'NSAppTransportSecurity' not in info
plistlib.loads((ios/'WorkMemory/PrivacyInfo.xcprivacy').read_bytes())
assert 'DEVELOPMENT_TEAM' not in (root/'README.md').read_text() or '自己的' in (root/'README.md').read_text()
for name in ['WorkMemory/SettingsView.swift','WorkMemory/MemoryViews.swift','WorkMemory/AIController.swift','Core/AIService.swift']:
    assert name in project, f'Unwired source: {name}'
print('Project references, microphone/background mode, and HTTPS policy: passed')
