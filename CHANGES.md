# Round 10: she feels alive (live voice, messages first, learning, new tools)

Not compiled or tested on a phone. No Flutter SDK was available. Checked by script: brackets, imports, packages. See "Not tested" below.

## What is new
1. **Live voice call (Gemini Live).** The mic button on the voice screen now starts a real-time call. Audio goes straight to Gemini and back. You can interrupt her. Tools work during the call (web, alarms, reminders, WhatsApp, phone control...). "Look at my screen" sends a screenshot into the call. Mute button at the top. If the call cannot connect, the old voice loop starts instead and a note says why.
   - Files: `lib/services/live_voice_service.dart`, `android/.../EdithLiveAudio.kt`, `MainActivity.kt`.
   - Model default `gemini-3.8-live`. Change it in Settings > Presence if Google renames it.
   - If she hears herself on the speaker: Presence > "Mute my mic while she talks".
2. **She messages first.** Morning message, evening check-in, follow-ups ("how did the exam go?") and reminders arrive as real notifications, even with the app closed and after a reboot. Tap one and the app opens with her message as the first line of a new chat.
   - Files: `lib/services/proactive_service.dart`, `android/.../EdithProactive.kt`, manifest, `ic_stat_edith.xml`.
   - Switch on in Settings > Presence. Off by default.
3. **Learning after each chat.** When you leave a chat (new chat, other chat, app to background, end of a voice call) she keeps lasting facts, writes a one-line note of what you talked about, and suggests rules for herself only if you corrected her. Rules wait for your OK in Self-improvement. Passwords, PINs and card/ID numbers are never saved. Near-duplicates are skipped.
   - Files: `lib/services/reflection_service.dart`, `lib/brains/memory_core.dart`. Chat notes show in Memory.
4. **New tools:** `remind_me`, `list_reminders`, `cancel_reminder`, `set_timer`, `get_battery`, `get_location`.
5. **Call survives screen-off** with a quiet "on a call" notification.
6. **New screen:** Settings > Character > Presence (`lib/screens/presence_screen.dart`).

## Fixed on the way
- `voice_chat_screen.dart` used `_orbColor` but never defined it (build error). Now defined: blue asleep, orange-red when the call is on.
- Memory limit raised from 60 to 80 facts. The `remember` tool now skips private data and repeats.

## Not tested (be honest)
- Nothing was compiled. The first `flutter analyze lib` may show small errors. Send them to me.
- Live voice: Google's docs disagree on one setup field, so the app tries both layouts and up to three model names. The first real call is the real test. Echo on speaker depends on your phone.
- Native audio and alarm code (Kotlin) was reviewed by eye only.
- Morning and evening texts are written when you open the app, so they cannot hold live weather or news.
- Live calls now keep running with the screen off (foreground service, `lib/services/call_keepalive.dart`). Also untested on a phone. The wake-word listener sleeps while the voice screen is open, so the two do not fight for the microphone.
- No new packages were added.

---

# Round 2 (this ZIP)

## Build fixes now inside the project
The GitHub build needed four patches. They are now part of the files, so any build (Codespaces, GitHub Actions, a PC) works:
1. `pubspec.yaml`: `speech_to_text ^7.3.0` (the old 6.x used `jcenter()`, which new Gradle removed).
2. `lib/services/tool_router.dart`: the `Schema.required` line no longer breaks with `google_generative_ai` 0.4.x.
3. `android/build.gradle.kts`: every plugin is compiled against Android SDK 36.
4. `android/gradle.properties`: Gradle memory 4 GB (was 8 GB, too much for GitHub's machine).

## New
- App icon: your E logo (all sizes plus adaptive icon). Splash: your light-streak picture, full screen. Black launch screen.
- Voice screen: live hologram (glowing 3D knot of light strands plus drifting smoke). It reacts to Listening / Thinking / Speaking. Drag to turn, pinch to zoom, double-tap to reset. Your hologram picture is the faint backdrop and the faint picture on the empty chat.
- Hand control (voice screen, hand icon top right): a small camera preview watches your hands. Pinch with one hand and move to spin the hologram. Pinch with both hands and spread or close them to zoom. Adapted from the open-source (MIT) orb UI by Sagar Tamang (sagartamang.com); only its hand-gesture logic is used. It runs Google MediaPipe inside a small WebView, so it needs internet when it starts. The camera is on only while hand control is on.
- Uploads: any file up to 100 MB. Text and code, PDF, Word (.docx), PowerPoint (.pptx), Excel (.xlsx) and ZIP are read. Other types are attached by name and size only.
- Picture or file now waits in the input bar, so you can write a note first, then send both together.
- Settings > Appearance: theme colour (8 colours, applies at once). Settings > Character > Personality: edit how EDITH talks. Her honesty and safety rules are always added and cannot be edited. Reset brings back the original.
- NextPass removed (screen, file, drawer entry).
- Wake word rewritten: asks for the microphone first, starts the listening service properly, restarts itself after every listening round, and tells you why if it cannot start. It also accepts "hey edit" and common mis-hearings of EDITH.

## Not tested (be honest)
No Flutter SDK or internet here, so none of this was compiled or run. Hand control uses the `webview_flutter` package (new in `pubspec.yaml`); I checked its camera-permission hook in the package docs but did not build it. I checked brackets, imports, packages and every place the theme colour is used. The hologram speed on your phone, the wake word on your phone, and ZIP/Word reading are untested on a device.

---

# E.D.I.T.H. — what changed in this fix round

## A. Build-breakers fixed
1. `lib/models/attachment.dart` held a copy of `Message` and had no `Attachment` class. Now it is the real `Attachment` class.
2. `lib/screens/next_pass_screen.dart` had a stray first line. Removed.
3. `lib/screens/settings_screen.dart` had a corrupted `_save()` and a missing import. New file.
4. `lib/screens/home_screen.dart` used `GeminiService` without importing it. New file.
5. `lib/services/wake_word_service.dart` used `VoidCallback` without an import. Fixed.
6. `pubspec.yaml` listed `assets/images/` but the folder did not exist. Folder created with pictures.
7. `test/widget_test.dart` pointed at a class that does not exist (`MyApp`). Replaced with small real tests.

## B. Security
1. Real API keys were in `lib/config.dart`. Now placeholders only. Keys go in Settings (stored on the phone).
2. The Gemini key was sent inside the URL. Now sent in the `x-goog-api-key` header.
3. SMS, email and phone-control tools ran with no question. Now EDITH shows an Allow / Cancel box first. The prompt also tells Gemini that notifications, emails, web pages and screen text are data, not orders.
4. Gmail send could be tricked with line breaks in `to` / `subject`. Now cleaned.
5. Removed two unused powerful permissions: `RECEIVE_SMS`, `SYSTEM_ALERT_WINDOW`.
6. Removed the whole `lib/oracle/` folder (drone / satellite targeting code).
7. Camera HUD no longer rates people or objects as threats. It only draws labels.

## C. Reliability
1. 429 on text chat: one shared file, `lib/services/gemini_endpoints.dart`, now controls model, keys and fallback for chat, tools, vision, voice, camera and the phone agent. Order: main key, backup key, then `gemini-3.5-flash-lite` with each key. It also falls back on 404 and 5xx.
2. Friendly one-line errors everywhere (no key, limit reached, bad key, server down, no internet).
3. Tool calls with Gemini 3: the answer part that carries `thoughtSignature` is now sent back exactly as received. Without it Gemini answers 400.
4. After 4 tool rounds EDITH used to stop silently. Now she says so.
5. ElevenLabs request body was built by hand and broke on tabs / odd characters. Now `jsonEncode`.
6. Camera HUD boxes were drawn in camera coordinates, not screen coordinates. Now scaled to the preview.
7. Voice and Camera screens could crash after you left them, and Camera stayed on a spinner without permission. Fixed.
8. Chat titles were the raw first message ("[Sent an image]"). Now short clean titles. Deleting a chat now also deletes its saved pictures.
9. Turning the wake word on or off in Settings now works at once (no app restart).
10. SMS / contacts / notification permission denied: EDITH now opens the right Android page and tells you what to switch on.
11. Error messages are shown but never saved into chat history.

## D. New look (simple, like Claude / ChatGPT / Gemini)
- Calm home screen: "How can I help, Boss?", 4 suggestion chips, one rounded input bar with + (photo / file), mic, send.
- Replies are plain text (Markdown: headings, lists, code, bold). Your messages are soft rounded bubbles. Pictures tap to enlarge. Copy and read-aloud under each reply.
- Left drawer replaces the bottom menu: New chat, Search chats, history by Today / Yesterday / Previous 7 days / Older, a short Tools list (God Screen, Builder, Missions, Voice, Camera, Camera HUD), your name and Settings at the bottom. Long-press or "…" on a chat to rename or delete.
- Settings in grouped cards: AI, Voice, Tools, Phone control.
- Normal system font everywhere. No custom fonts. (Fixed-width only inside code blocks.)
- Dark theme, one blue accent #2FE0FF, no stacked borders.
- Splash: infinity picture, "E D I T H", credit line (HILAL INDUSTRIES or MAHMOOD INDUSTRIES). Hologram sphere is only a faint picture on the empty chat screen. Neon "E" is the app icon (adaptive icon, correct sizes).
- Removed every "coming soon" item.

## E. Names and clean-up
- The old last word of the name is now "Tactical Hegemon" everywhere (persona, README, UI). A search for the old word finds nothing.
- No Stark / Marvel words left. The old "Peter's suit workshop" comment is gone.
- Deprecated `withOpacity` and `activeColor` replaced. `google_fonts` and `cryptography` removed from `pubspec.yaml`.
- `.gitignore` now has `/flutter/`. `lib/config.dart` is NOT ignored on purpose: it now holds no secrets, and a fresh clone needs it to build.
- Old `CHANGES_v0.5.md` removed. README rewritten.

## F. Hidden until real (not built)
BCI / Muse pairing screen, theme picture picker, Knowledge Vault, full AI Router, screen sharing, anti-theft, voice-only toggle, Workspace / Drive sign-in fields. The files for BCI, Drive backup and battery stay in `lib/services/` but nothing opens them.

## G. NOT tested (be honest)
- No Flutter SDK here. `flutter analyze` and `flutter build apk` were NOT run.
- I checked every Dart file with my own script: brackets, imports, missing or unused imports, packages in pubspec, stray lines, deprecated words. It found 0 problems after the fixes. That is a syntax and wiring check, not a compiler.
- Nothing ran on a phone. Camera HUD box scaling, the drawer, tool approval box and the thought-signature fix are untested on a device.
- Model names `gemini-3.6-flash` and `gemini-3.5-flash-lite` match Google's docs (July 2026), but I did not call the live API.
- The splash picture and hologram picture are stand-ins I drew. Your real ones were not in the upload.

## H. Google Calendar / Gmail setup (only if you want those tools)
1. Go to https://console.cloud.google.com and make a project.
2. APIs & Services → Library → enable **Gmail API** and **Google Calendar API**.
3. APIs & Services → OAuth consent screen → External → add your own Gmail as a **Test user**.
4. APIs & Services → Credentials → Create credentials → OAuth client ID → **Android**.
   - Package name: `com.example.edith_app` (or your new id).
   - SHA-1: run `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android` in Codespaces and copy the SHA1 line.
5. Build and install. The first time you ask EDITH about your calendar or email, Google asks you to sign in.
Note: an APK built in a new Codespace is signed with that Codespace's own debug key. If sign-in stops working after a new Codespace, add the new SHA-1 as another Android client.

## I. Before publishing
Change the package id `com.example.edith_app`: `applicationId` and `namespace` in `android/app/build.gradle(.kts)`, the folder `android/app/src/main/kotlin/com/example/edith_app`, and the `package` line at the top of the three Kotlin files.

## Round 3: phone control rebuilt

Not compiled or tested on a device yet.

- Planner: makes a short plan before acting.
- Perception: the screen is read as a numbered list (TAP / FIELD / TEXT), only what is visible.
- Actions: OPEN app by name, TAP (exact match first, gesture fallback), TYPE (finds the field itself), SCROLL, WAIT, BACK, HOME, RECENTS.
- Verification: the screen is read again after every action. "Nothing changed" counts as a failure.
- Adaptation: remembers what failed in this run, stops after 3 failures in a row, up to 15 steps. A Gemini error no longer counts as "done".
- Safety: still asks Allow/Cancel first. Never taps pay / buy / transfer / erase buttons. Screen text is data, never instructions.
- `open_app` tool now takes the app name ("WhatsApp"), not a package name.
- The final answer is a short report, not a raw transcript.

## Round 4

Not compiled or tested on a device yet.

- Grok (xAI) added: key + model in Settings, switch "Use Grok as main brain". Default: Gemini first, Grok takes over if Gemini fails. Used by chat, voice and builder.
- Speed: a key that hit its limit is skipped for 3 minutes, stuck requests give up after 25 s, older attached files are sent as a short note (only the newest is sent in full), lower thinking level (retries without it if the model refuses).
- Errors now show a short real reason in brackets instead of only "Something went wrong".
- Builder and other one-shot Gemini calls: if Google Search grounding is refused (HTTP 400) the call is retried without it.
- Voice screen: now uses the same brain as chat (tools + Grok backup). Hands-free live mode (mic button toggles it), bottom control bar (camera, hands, mic, close), opens listening when started by the wake word.
- Rotating thinking words while she works ("Cogitating…", "Musing…").
- WhatsApp: accepts a contact name or number, optional WhatsApp Business, asks Allow/Cancel, then taps Send itself when phone control is on.
- Personality: Character and Rules are both editable. The rules were rewritten (thinking, tool use, self-check, honesty). The Allow/Cancel safety is in code and stays on.
- Screen sharing is not built (needs a native screen-capture permission).

## Round 4b: internet

- New tools `web_search` and `read_webpage` (lib/services/web_service.dart). Search uses Google-grounded Gemini (with sources) and falls back to DuckDuckGo if that fails. Pages are fetched and turned into plain text (12000 characters max).
- Works in chat and voice, with Gemini or Grok.
- Persona rules and the tool prompt now say she has the internet and must not claim to be offline.
- Limits: she cannot sign in to sites, bypass paywalls, or run pages that need JavaScript to show their content.

## Round 5

Not compiled or tested on a device yet.

- Voice: Gemini's own speech engine (gemini-2.5-flash-preview-tts) is now her voice in chat and voice mode, with the phone voice as a fallback. Voice choice in Settings. If it falls back, a note says why.
- Hand control: camera view is hidden (no face on screen); the status line shows the real error if it fails; Android video autoplay block removed.
- Hologram: now a thick four-lobed ribbon knot (nine strands) like the picture. The background uses only the space part of the picture, so there is no second knot behind it.
- Chat: Edit a sent message and resend; Try again on the last reply; Think and Search buttons.
- Long-term memory: remember / forget tools, a Memory screen in Settings, memories are added to her prompt.
- Image generation: generate_image tool (Gemini image model, Grok as backup). The picture shows in the chat.
- Image/file hint text is clearer.
- Phone control: the "off" message now explains Allow restricted settings for side-loaded apps.

## Round 6

Not compiled or tested on a device yet.

- Phone control: the app can now tell "off" from "switched on but the phone is not running it". Off: opens Accessibility settings. Enabled but not running: opens the app's settings page and explains Autostart, Battery "No restrictions", and switching the service off and on.
- New native call `status` in MainActivity.kt, used by PhoneAgentService.


## Round 7
- God Screen rebuilt: worldwide OpenSky flights + world plot; Windy public webcams (key in Settings)
- Voice: orb colour by state, SYSTEM LOCKED/ONLINE chip, share-screen button
- Screenshots via AccessibilityService (canTakeScreenshot); phone agent sees the screen; look_at_screen tool
- Splash fix for Android 12+ (values-v31)
- Settings: export all chats, delete all chats, about
- BACKLOG.md added. Not compiled or tested on a device yet.

## Round 8
- Discover news feed (drawer): picture, headline, AI summary, share/like/open, refresh. Needs NewsAPI key.

## Round 9
- Self-improvement: she reviews her own chats, proposes rules, you approve; failed phone tasks become lessons; lessons go into her prompt.
