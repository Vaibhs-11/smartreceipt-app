# AGENTS.md

## Project
ReceiptNest is a Flutter mobile app for receipt scanning, organisation, collections, insights, exports, and Firebase-backed OCR/enrichment.

## Working rules
- Always investigate before patching.
- Prefer small, surgical diffs.
- Do not refactor unrelated files.
- Do not change app architecture unless explicitly requested.
- Do not touch Podfile, Podfile.lock, project.pbxproj, GeneratedPluginRegistrant, Firebase plist/json files, signing settings, or deployment config unless the task explicitly requires it.
- Do not change Firestore rules, Cloud Functions deployment config, or Firebase project settings without explicit approval.
- Preserve existing Riverpod patterns and naming conventions.
- Keep changes additive and backwards-compatible where possible.
- For entitlement, trial, subscription, receipt limits, and collection logic, be extra conservative.

## Validation commands
Run only the relevant checks for the changed area.

Flutter:
- flutter pub get
- flutter analyze
- flutter test

iOS:
- cd ios && pod install only if dependency or iOS config changed
- Do not modify Podfile unless explicitly requested

Functions:
- cd functions && npm install only if package files changed
- cd functions && npm run build
- Do not deploy functions unless explicitly requested

## Expected response format
Before editing:
1. Root cause
2. Files involved
3. Proposed change
4. Risk level

After editing:
1. Files changed
2. What changed
3. Validation performed
4. Any remaining risk