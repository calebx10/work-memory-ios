# Working on WorkMemory

This is a native SwiftUI iPhone app, not a website. The current scope is iPhone-only daily use; `docs/ORIGINAL_PRD.md` is historical and does not override `docs/PRD.md` or the user's current request.

## Personal installation

Read `docs/INSTALL.md` and `docs/CODEX_QUICKSTART.md`. Use the user's own Apple account and unique bundle ID. Never ask for Apple passwords, verification codes, or API keys in chat. Apple authentication happens in Apple's UI; API keys are entered in the app and stored in Keychain.

`python3 scripts/generate_project.py --team-id YOUR_TEAM_ID --bundle-id com.yourname.workmemory` writes identity only to the ignored `app/ios/WorkMemory/Signing.local.xcconfig`. Never commit that file, provisioning profiles, certificate private keys, real recordings, or exported memory documents. Run the generator when adding/removing Swift files. The shared Xcode project is generated deterministically.

Before updating an existing installation, check its bundle ID and signing team. Preserve both. Do not uninstall the app to fix a build: that deletes local recordings. Do not replace real user data with UI test fixtures. Debug UI tests use a separate sandbox directory and synthetic audio only.

## Validation

Run `swift test` and `python3 scripts/check_project.py` for relevant changes. Verify project/signing changes with `xcodebuild -project app/ios/WorkMemory.xcodeproj -scheme WorkMemory -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/simulator CODE_SIGNING_ALLOWED=NO build`. A signed device build needs the user's own credentials. Do not claim real microphone, lock-screen longevity, interruptions, or paid AI are tested merely because compilation passes. See `docs/TEST_PLAN.md` for actual limits.

## Privacy and cost

Recording remains local until the user confirms analysis. Never automatically upload recordings or make paid AI requests during setup/tests. Use mock services for tests. Never print keys or raw user transcripts in logs. Preserve successful checkpoints and manual retry behavior; do not add automatic paid retry loops. APIMart receives audio; DeepSeek receives text in the combination preset, with independent credentials and explicit consent.

## Scope

Follow the user's requested change. Do not publish a fork, alter repository visibility, buy developer membership, change AI providers, or enable automatic uploads as a side effect of personal installation.
