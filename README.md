# E.D.I.T.H.

**Eminent Digital Intelligence & Tactical Hegemon** — a personal AI assistant
for Android, built by Hilal.

Chat with streaming replies, tools (weather, news, SMS, calendar, phone
control), photo and file questions, voice, and saved chats.

## First run

1. Install the app (see Build below).
2. Open the left menu, tap the gear (Settings).
3. Paste your Gemini key. Get one free at https://aistudio.google.com/apikey
4. Optional: a backup Gemini key from a *different* Google account,
   ElevenLabs, OpenWeather and NewsAPI keys.
5. Tap Save.

Keys are stored only on the phone. Never paste keys into code files.

## Build (GitHub Codespaces)

```
cd /workspaces/edith/edith_app
flutter pub get
flutter analyze lib
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`

Do not put a Flutter SDK folder inside this project.

## Pictures

- `assets/images/splash_logo.jpg` — splash screen picture.
- `assets/images/hologram_bg.jpg` — very faint art on the empty chat screen.
- App icon: put your picture at `app_icon.jpg` in this folder, then run
  `python3 tools/make_icons.py app_icon.jpg`. It rewrites the Android icons.

## Project map

```
lib/
  main.dart                      app start
  config.dart                    placeholders only (no real keys)
  theme/edith_theme.dart         dark theme, system font, blue accent
  brains/                        persona, memory (chats), missions, builder
  models/                        message, attachment, chat thread, ...
  services/gemini_endpoints.dart model + key + fallback for every Gemini call
  services/tool_router.dart      chat with tools (main path)
  services/tool_executor.dart    runs the tools; asks before SMS/email/phone control
  widgets/edith_drawer.dart      left menu
  widgets/markdown_lite.dart     renders replies
  screens/                       home, settings, God Screen, Builder, ...
android/                         accessibility + notification services (Kotlin)
```

## Before publishing

- Change the package id `com.example.edith_app` (in `android/app/build.gradle*`
  and the Kotlin folder name).
- Google Calendar / Gmail tools need a Google Cloud OAuth client. See CHANGES.md.
