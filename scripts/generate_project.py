#!/usr/bin/env python3
"""Generate a dependency-free Xcode project with deterministic object IDs."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
ios = root / 'app/ios'
project = ios / 'WorkMemory.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}
existing_project = project / 'project.pbxproj'
existing = existing_project.read_text() if existing_project.exists() else ''
match = re.search(r'DEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]+)', existing)
team_id = match.group(1) if match else None
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(name, text):
    objects[uid(name)] = text
    return uid(name)
def q(s): return json.dumps(str(s), ensure_ascii=False)
def array(values): return '(' + ', '.join(values) + ',)'
source_refs, source_builds = [], []
for file in sorted(ios.glob('Core/*.swift')) + sorted(ios.glob('WorkMemory/*.swift')):
    path = file.relative_to(ios).as_posix()
    ref = add('file:'+path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = "<group>";')
    source_refs.append(ref)
    source_builds.append(add('build:'+path, f'isa = PBXBuildFile; fileRef = {ref};'))
info = add('info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = WorkMemory/Info.plist; sourceTree = "<group>";')
privacy = add('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = WorkMemory/PrivacyInfo.xcprivacy; sourceTree = "<group>";')
privacy_build = add('privacy-build', f'isa = PBXBuildFile; fileRef = {privacy};')
assets = add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = WorkMemory/Assets.xcassets; sourceTree = "<group>";')
assets_build = add('assets-build', f'isa = PBXBuildFile; fileRef = {assets};')
app = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = WorkMemory.app; sourceTree = BUILT_PRODUCTS_DIR;')
ui_file = add('ui-file', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WorkMemoryUITests/WorkMemoryUITests.swift; sourceTree = "<group>";')
ui_product = add('ui-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = WorkMemoryUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; name = Products; children = {array([app,ui_product])}; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = {array(source_refs+[ui_file,info,privacy,assets,products])}; sourceTree = "<group>";')
sources = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array([privacy_build,assets_build])}; runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for name in ['Debug','Release']:
    config = {
        'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0',
        'CLANG_ENABLE_MODULES':'YES', 'ENABLE_STRICT_OBJC_MSGSEND':'YES',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O',
        'DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym',
        'ENABLE_TESTABILITY':'YES' if name=='Debug' else 'NO',
    }
    def settings(d): return '{' + ''.join(f'{k} = {q(v)};' for k,v in d.items()) + '}'
    project_configs.append(add('project-'+name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {settings(config)};'))
    target = {
        'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':'com.workmemory.personal',
        'INFOPLIST_FILE':'WorkMemory/Info.plist','GENERATE_INFOPLIST_FILE':'NO',
        'CODE_SIGN_STYLE':'Automatic', 'TARGETED_DEVICE_FAMILY':'1',
        'CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0',
        'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
        'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon',
        'SWIFT_EMIT_LOC_STRINGS':'YES', 'SWIFT_STRICT_CONCURRENCY':'targeted',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if name=='Debug' else '',
    }
    if team_id: target['DEVELOPMENT_TEAM'] = team_id
    target_configs.append(add('target-'+name,f'isa = XCBuildConfiguration; name = {name}; buildSettings = {settings(target)};'))
pconfigs = add('project-config-list', f'isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tconfigs = add('target-config-list', f'isa = XCConfigurationList; buildConfigurations = {array(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add('target', f'isa = PBXNativeTarget; name = WorkMemory; productName = WorkMemory; productReference = {app}; productType = "com.apple.product-type.application"; buildConfigurationList = {tconfigs}; buildPhases = {array([sources,frameworks,resources])}; buildRules = (); dependencies = ();')
ui_build = add('ui-build', f'isa = PBXBuildFile; fileRef = {ui_file};')
ui_sources = add('ui-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array([ui_build])}; runOnlyForDeploymentPostprocessing = 0;')
ui_frameworks = add('ui-frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
ui_configs = []
for name in ['Debug', 'Release']:
    config = {'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':'com.workmemory.personal.uitests', 'GENERATE_INFOPLIST_FILE':'YES', 'CODE_SIGN_STYLE':'Automatic', 'TEST_TARGET_NAME':'WorkMemory', 'TARGETED_DEVICE_FAMILY':'1', 'SWIFT_VERSION':'5.0'}
    if team_id: config['DEVELOPMENT_TEAM'] = team_id
    ui_configs.append(add('ui-config-'+name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {settings(config)};'))
ui_config_list = add('ui-config-list', f'isa = XCConfigurationList; buildConfigurations = {array(ui_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
proxy = add('ui-proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = WorkMemory;')
dependency = add('ui-dependency', f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
ui_target = add('ui-target', f'isa = PBXNativeTarget; name = WorkMemoryUITests; productName = WorkMemoryUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing"; buildConfigurationList = {ui_config_list}; buildPhases = {array([ui_sources,ui_frameworks])}; buildRules = (); dependencies = {array([dependency])};')
proj = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {pconfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; knownRegions = (zh_CN, en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([target,ui_target])};')
text = '// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text += '\n'.join(f'{id} = {{{body}}};' for id,body in objects.items())
text += f'\n}}; rootObject = {proj};}}\n'
(project/'project.pbxproj').write_text(text)
scheme = project/'xcshareddata/xcschemes/WorkMemory.xcscheme'
scheme.parent.mkdir(parents=True, exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="WorkMemory.app" BlueprintName="WorkMemory" ReferencedContainer="container:WorkMemory.xcodeproj"/>'
test_ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="WorkMemoryUITests.xctest" BlueprintName="WorkMemoryUITests" ReferencedContainer="container:WorkMemory.xcodeproj"/>'
scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {project} ({len(source_refs)} Swift sources)')
