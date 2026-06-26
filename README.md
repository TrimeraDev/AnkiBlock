# AnkiBlock

**Study first. Unlock freedom.**

AnkiBlock blocks distracting Android apps until you complete your Anki cards in [AnkiDroid](https://play.google.com/store/apps/details?id=com.ichi2.anki). Your flashcards stay in AnkiDroid — AnkiBlock reads your real study progress locally and enforces the gate.

- **Website:** [trimeradev.github.io/AnkiBlock](https://trimeradev.github.io/AnkiBlock/)
- **Privacy policy:** [trimeradev.github.io/AnkiBlock/privacy.html](https://trimeradev.github.io/AnkiBlock/privacy.html)
- **Imprint:** [trimeradev.github.io/AnkiBlock/imprint.html](https://trimeradev.github.io/AnkiBlock/imprint.html)

AnkiBlock is a non-commercial open-source project published by Simon & Vincent UG (haftungsbeschränkt). It is **not** affiliated with Anki, AnkiWeb, or the AnkiDroid project.

## Features

- Block chosen apps (social media, games, etc.) behind a study gate
- Connect to AnkiDroid via its public ContentProvider API
- Set cards required per unlock, daily goals, and unlock duration
- Choose which AnkiDroid decks count toward your queue
- Track daily stats on-device — no account, no cloud backend

## Requirements

- **Android** device or emulator
- **[AnkiDroid](https://play.google.com/store/apps/details?id=com.ichi2.anki)** installed
- **[Flutter](https://docs.flutter.dev/get-started/install)** 3.22+ and Dart 3.4+
- Android SDK with JDK 17 (for native Android builds)

AnkiBlock also needs Android permissions for usage access, overlay display, and AnkiDroid database access. The app guides you through granting these during onboarding.

## Getting started

```bash
git clone https://github.com/TrimeraDev/AnkiBlock.git
cd AnkiBlock
flutter pub get
flutter run
```

For a release APK:

```bash
flutter build apk --release
```

The output is at `build/app/outputs/flutter-apk/app-release.apk`.

### Code generation

This project uses [Drift](https://drift.simonbinder.eu/) for local storage. After changing `lib/src/core/database/database.dart`, regenerate:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Architecture (short)

| Layer | Role |
|-------|------|
| **Flutter (Dart)** | UI, settings, local SQLite via Drift, Riverpod state |
| **Android (Kotlin)** | App monitor service, study gate overlay, AnkiDroid ContentProvider bridge |

AnkiDroid remains the source of truth for cards, decks, and scheduling. AnkiBlock only stores blocker settings and daily stats.

## Contributing

Issues and pull requests are welcome on GitHub. For bugs or privacy questions, you can also email [ankiblock@trimera.dev](mailto:ankiblock@trimera.dev).

Please do not commit signing keys, keystores, or other secrets.

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 Simon & Vincent UG (haftungsbeschränkt).
