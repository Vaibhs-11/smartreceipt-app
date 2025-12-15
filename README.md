    # SmartReceipt — Mobile-first receipt scanning & organisation app

This is a Flutter project skeleton implementing a scalable, clean architecture for SmartReceipt. It is wired to Firebase, Cloud Functions, and OpenAI for OCR-powered receipt capture.

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

The app relies on Firebase services and OpenAI for OCR parsing, so make sure your `.env` contains valid keys before running.

## Project Structure

```
lib/
  core/            # config, constants, theme
  data/            # repositories impls and external services
  domain/          # entities, repositories (abstract), use-cases
  presentation/    # UI, screens, providers, routes
```

## Environment

The app attempts to load `.env` but does not require it locally. For reference, create `config/env.example` and copy to `.env` if needed.

## Premium Features Wiring (Later)

- Configure Firebase (via FlutterFire) and provide environment variables such as `OPENAI_API_KEY`.
- Configure `codemagic.yaml` and connect the repo in Codemagic for CI/CD builds.
