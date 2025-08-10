# SmartReceipt — Mobile-first receipt scanning & organisation app

This is a Flutter project skeleton implementing a scalable, clean architecture for SmartReceipt. It runs locally without any API keys using stubbed services and can be wired to Firebase, Google Vision, and OpenAI later.

## Requirements

- Flutter 3.22+ (Dart 3.4+)
- macOS or Windows/Linux

## Getting Started

1. Install Flutter and run `flutter doctor`.
2. From the project root, generate platform scaffolding (only once):

```
flutter create .
```

3. Install packages and run:

```
flutter pub get
flutter run
```

The app uses stubs for OCR, AI tagging, notifications, and auth so it works offline by default.

## Project Structure

```
lib/
  core/            # config, constants, theme
  data/            # repositories impls and services (stubs)
  domain/          # entities, repositories (abstract), use-cases
  presentation/    # UI, screens, providers, routes
```

## Environment

The app attempts to load `.env` but does not require it locally. For reference, create `config/env.example` and copy to `.env` if needed.

## Premium Features Wiring (Later)

- Replace service stubs in `presentation/providers/providers.dart` with real implementations when keys are present.
- Add Firebase initialization in `main.dart` guarded by `AppConfig`.
 - Configure `codemagic.yaml` and connect the repo in Codemagic for CI/CD builds.
