import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Settings Service — v0.5
///
/// Reads/writes user-editable settings (API keys, voice preferences) to
/// local storage. Call [SettingsService.init] once in main() before
/// runApp() so every getter below works synchronously afterward.
///
/// Falls back to the hardcoded defaults in AppConfig when the user hasn't
/// entered anything yet, so this doesn't break anyone still relying on
/// config.dart directly.
class SettingsService {
  SettingsService._();

  static late SharedPreferences _prefs;
  static bool _initialized = false;

  static const _kGeminiKey = 'settings_gemini_api_key';
  static const _kGeminiKeyBackup = 'settings_gemini_api_key_backup';
  static const _kElevenKey = 'settings_elevenlabs_api_key';
  static const _kElevenVoiceId = 'settings_elevenlabs_voice_id';
  static const _kAutoSpeak = 'settings_auto_speak';
  static const _kUseElevenLabs = 'settings_use_elevenlabs';
static const _kWeatherKey = 'settings_openweather_api_key';
  static const _kNewsKey = 'settings_newsapi_key';
  static const _kWakeWord = 'settings_wake_word_enabled';
  static const _kAccent = 'settings_accent_color';
  static const _kPersona = 'settings_persona_text';
  static const _kRules = 'settings_rules_text';
  static const _kGrokKey = 'settings_grok_api_key';
  static const _kGrokModel = 'settings_grok_model';
  static const _kPreferGrok = 'settings_prefer_grok';
  static const _kGeminiVoice = 'settings_gemini_voice';
  static const _kUseGeminiVoice = 'settings_use_gemini_voice';
  static const _kMemories = 'settings_memories';
  static const _kWindyKey = 'settings_windy_api_key';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  static void _assertInit() {
    assert(
      _initialized,
      'SettingsService.init() must be awaited in main() before runApp().',
    );
  }

  static String get geminiApiKey {
    _assertInit();
    final stored = _prefs.getString(_kGeminiKey);
    return (stored != null && stored.isNotEmpty)
        ? stored
        : AppConfig.geminiApiKey;
  }

  static Future<void> setGeminiApiKey(String value) async {
    _assertInit();
    await _prefs.setString(_kGeminiKey, value.trim());
  }

  /// Backup key from a genuinely separate Google account/project — the
  /// only kind that actually helps on a 429, since Gemini's free-tier
  /// quota is tied to the Cloud project, not the individual key. A
  /// second key from the SAME account shares the same exhausted quota.
  static String get geminiApiKeyBackup {
    _assertInit();
    return _prefs.getString(_kGeminiKeyBackup) ?? '';
  }

  static Future<void> setGeminiApiKeyBackup(String value) async {
    _assertInit();
    await _prefs.setString(_kGeminiKeyBackup, value.trim());
  }

  static bool get hasGeminiKeyBackup => geminiApiKeyBackup.isNotEmpty;

  static String get elevenLabsApiKey {
    _assertInit();
    final stored = _prefs.getString(_kElevenKey);
    return (stored != null && stored.isNotEmpty)
        ? stored
        : AppConfig.elevenLabsApiKey;
  }

  static Future<void> setElevenLabsApiKey(String value) async {
    _assertInit();
    await _prefs.setString(_kElevenKey, value.trim());
  }

  static String get elevenLabsVoiceId {
    _assertInit();
    final stored = _prefs.getString(_kElevenVoiceId);
    return (stored != null && stored.isNotEmpty)
        ? stored
        : AppConfig.elevenLabsVoiceId;
  }

  static Future<void> setElevenLabsVoiceId(String value) async {
    _assertInit();
    await _prefs.setString(_kElevenVoiceId, value.trim());
  }

  /// Whether replies are spoken automatically via the free device voice.
  static bool get autoSpeak {
    _assertInit();
    return _prefs.getBool(_kAutoSpeak) ?? true;
  }

  static Future<void> setAutoSpeak(bool value) async {
    _assertInit();
    await _prefs.setBool(_kAutoSpeak, value);
  }

  /// Whether to use the higher-quality (credit-limited) ElevenLabs voice
  /// instead of the free unlimited device voice.
  static bool get useElevenLabs {
    _assertInit();
    return _prefs.getBool(_kUseElevenLabs) ?? false;
  }

  static Future<void> setUseElevenLabs(bool value) async {
    _assertInit();
    await _prefs.setBool(_kUseElevenLabs, value);
  }

  /// True once the user has entered a real key (vs. still holding the
  /// PASTE_YOUR_..._HERE placeholder shipped in config.dart).
  static bool get hasGeminiKey =>
      geminiApiKey.isNotEmpty && !geminiApiKey.startsWith('PASTE_');

  static bool get hasElevenLabsKey =>
      elevenLabsApiKey.isNotEmpty && !elevenLabsApiKey.startsWith('PASTE_');
static String get openWeatherKey {
    _assertInit();
    return _prefs.getString(_kWeatherKey) ?? '';
  }

  static Future<void> setOpenWeatherKey(String value) async {
    _assertInit();
    await _prefs.setString(_kWeatherKey, value.trim());
  }

  static String get newsApiKey {
    _assertInit();
    return _prefs.getString(_kNewsKey) ?? '';
  }

  static Future<void> setNewsApiKey(String value) async {
    _assertInit();
    await _prefs.setString(_kNewsKey, value.trim());
  }

  static bool get wakeWordEnabled {
    _assertInit();
    return _prefs.getBool(_kWakeWord) ?? false;
  }

  static Future<void> setWakeWordEnabled(bool value) async {
    _assertInit();
    await _prefs.setBool(_kWakeWord, value);
  }

  /// Theme accent colour (ARGB int). Defaults to EDITH cyan.
  static Color get accentColor {
    _assertInit();
    return Color(_prefs.getInt(_kAccent) ?? 0xFF2FE0FF);
  }

  static Future<void> setAccentColor(Color value) async {
    _assertInit();
    await _prefs.setInt(_kAccent, value.toARGB32());
  }

  /// Hilal's own version of EDITH's character text. Empty = use default.
  static String get personaText {
    _assertInit();
    return _prefs.getString(_kPersona) ?? '';
  }

  static Future<void> setPersonaText(String value) async {
    _assertInit();
    final v = value.trim();
    if (v.isEmpty) {
      await _prefs.remove(_kPersona);
    } else {
      await _prefs.setString(_kPersona, v);
    }
  }

  /// Hilal's own version of EDITH's rules text. Empty = use default.
  static String get rulesText {
    _assertInit();
    return _prefs.getString(_kRules) ?? '';
  }

  static Future<void> setRulesText(String value) async {
    _assertInit();
    final v = value.trim();
    if (v.isEmpty) {
      await _prefs.remove(_kRules);
    } else {
      await _prefs.setString(_kRules, v);
    }
  }

  static String get windyKey {
    _assertInit();
    return _prefs.getString(_kWindyKey) ?? '';
  }

  static Future<void> setWindyKey(String value) async {
    _assertInit();
    await _prefs.setString(_kWindyKey, value.trim());
  }

  // ───────────── Grok (xAI) ─────────────

  static const String defaultGrokModel = 'grok-4.7';

  static String get grokApiKey {
    _assertInit();
    return _prefs.getString(_kGrokKey) ?? '';
  }

  static Future<void> setGrokApiKey(String value) async {
    _assertInit();
    await _prefs.setString(_kGrokKey, value.trim());
  }

  static bool get hasGrokKey => grokApiKey.isNotEmpty;

  static String get grokModel {
    _assertInit();
    final m = _prefs.getString(_kGrokModel) ?? '';
    return m.isEmpty ? defaultGrokModel : m;
  }

  static Future<void> setGrokModel(String value) async {
    _assertInit();
    final v = value.trim();
    if (v.isEmpty || v == defaultGrokModel) {
      await _prefs.remove(_kGrokModel);
    } else {
      await _prefs.setString(_kGrokModel, v);
    }
  }

  /// When true (and a Grok key is set), Grok is the main brain and Gemini is
  /// not used for chat. When false, Gemini is main and Grok takes over if
  /// Gemini fails.
  static bool get preferGrok {
    _assertInit();
    return _prefs.getBool(_kPreferGrok) ?? false;
  }

  static Future<void> setPreferGrok(bool value) async {
    _assertInit();
    await _prefs.setBool(_kPreferGrok, value);
  }

  // ───────────── Gemini voice ─────────────

  static bool get useGeminiVoice {
    _assertInit();
    return _prefs.getBool(_kUseGeminiVoice) ?? true;
  }

  static Future<void> setUseGeminiVoice(bool value) async {
    _assertInit();
    await _prefs.setBool(_kUseGeminiVoice, value);
  }

  static String get geminiVoice {
    _assertInit();
    return _prefs.getString(_kGeminiVoice) ?? 'Kore';
  }

  static Future<void> setGeminiVoice(String value) async {
    _assertInit();
    await _prefs.setString(_kGeminiVoice, value);
  }

  // ───────────── Long-term memory ─────────────

  /// Short facts about Hilal that EDITH keeps between chats.
  static List<String> get memories {
    if (!_initialized) return const [];
    return _prefs.getStringList(_kMemories) ?? const [];
  }

  static Future<void> addMemory(String fact) async {
    _assertInit();
    final f = fact.trim();
    if (f.isEmpty) return;
    final list = List<String>.from(memories);
    if (list.any((m) => m.toLowerCase() == f.toLowerCase())) return;
    list.add(f.length > 300 ? f.substring(0, 300) : f);
    if (list.length > 80) list.removeAt(0);
    await _prefs.setStringList(_kMemories, list);
  }

  static Future<void> removeMemoryAt(int index) async {
    _assertInit();
    final list = List<String>.from(memories);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _prefs.setStringList(_kMemories, list);
  }

  /// Removes memories containing [text]. Returns how many were removed.
  static Future<int> forgetMatching(String text) async {
    _assertInit();
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return 0;
    final list = List<String>.from(memories);
    final before = list.length;
    list.removeWhere((m) => m.toLowerCase().contains(t));
    await _prefs.setStringList(_kMemories, list);
    return before - list.length;
  }

  static Future<void> clearMemories() async {
    _assertInit();
    await _prefs.remove(_kMemories);
  }

  // ───────────── Lessons (self-improvement) ─────────────

  static const _kLessons = 'settings_lessons';

  /// Short rules EDITH has learned from her own mistakes and feedback.
  static List<String> get lessons {
    if (!_initialized) return const [];
    return _prefs.getStringList(_kLessons) ?? const [];
  }

  static Future<void> addLesson(String text) async {
    _assertInit();
    final t = text.trim();
    if (t.isEmpty) return;
    final list = List<String>.from(lessons);
    if (list.any((m) => m.toLowerCase() == t.toLowerCase())) return;
    list.add(t.length > 240 ? t.substring(0, 240) : t);
    if (list.length > 30) list.removeAt(0);
    await _prefs.setStringList(_kLessons, list);
  }

  static Future<void> removeLessonAt(int index) async {
    _assertInit();
    final list = List<String>.from(lessons);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _prefs.setStringList(_kLessons, list);
  }
}
