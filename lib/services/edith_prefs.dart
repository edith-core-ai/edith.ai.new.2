import 'package:shared_preferences/shared_preferences.dart';

/// Switches and times for the "presence" features: live voice, proactive
/// messages and auto-learning. Kept apart from [SettingsService] so the
/// older settings code stays untouched.
///
/// Call [EdithPrefs.init] once in main() before runApp().
class EdithPrefs {
  EdithPrefs._();

  static SharedPreferences? _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static Future<SharedPreferences> _prefs() async =>
      _p ??= await SharedPreferences.getInstance();

  // ───────────── Live voice ─────────────

  static const String defaultLiveModel = 'gemini-3.8-live';
  static const String legacyLiveModel = 'gemini-3.1-flash-live-preview';

  static const _kLiveVoice = 'edith_live_voice';
  static const _kLiveModel = 'edith_live_model';
  static const _kHalfDuplex = 'edith_live_half_duplex';

  /// True: the mic button starts a real-time Gemini Live call.
  /// False: the older "listen, think, speak" loop.
  static bool get liveVoice => _p?.getBool(_kLiveVoice) ?? true;
  static Future<void> setLiveVoice(bool v) async =>
      (await _prefs()).setBool(_kLiveVoice, v);

  static String get liveModel {
    final m = _p?.getString(_kLiveModel) ?? '';
    return m.trim().isEmpty ? defaultLiveModel : m.trim();
  }

  static Future<void> setLiveModel(String v) async {
    final p = await _prefs();
    final t = v.trim().replaceFirst('models/', '');
    if (t.isEmpty || t == defaultLiveModel) {
      await p.remove(_kLiveModel);
    } else {
      await p.setString(_kLiveModel, t);
    }
  }

  /// Mutes the mic while she talks. Use it if she hears herself on the
  /// speaker. Turns off interrupting her by voice.
  static bool get halfDuplex => _p?.getBool(_kHalfDuplex) ?? false;
  static Future<void> setHalfDuplex(bool v) async =>
      (await _prefs()).setBool(_kHalfDuplex, v);

  // ───────────── Learning ─────────────

  static const _kAutoLearn = 'edith_auto_learn';

  /// She reads each finished chat and saves what is worth keeping.
  static bool get autoLearn => _p?.getBool(_kAutoLearn) ?? true;
  static Future<void> setAutoLearn(bool v) async =>
      (await _prefs()).setBool(_kAutoLearn, v);

  // ───────────── Proactive messages ─────────────

  static const _kProactive = 'edith_proactive';
  static const _kMorningOn = 'edith_morning_on';
  static const _kEveningOn = 'edith_evening_on';
  static const _kMorningMin = 'edith_morning_min';
  static const _kEveningMin = 'edith_evening_min';

  /// Master switch. Off by default: it needs the notification permission.
  static bool get proactive => _p?.getBool(_kProactive) ?? false;
  static Future<void> setProactive(bool v) async =>
      (await _prefs()).setBool(_kProactive, v);

  static bool get morningOn => _p?.getBool(_kMorningOn) ?? true;
  static Future<void> setMorningOn(bool v) async =>
      (await _prefs()).setBool(_kMorningOn, v);

  static bool get eveningOn => _p?.getBool(_kEveningOn) ?? true;
  static Future<void> setEveningOn(bool v) async =>
      (await _prefs()).setBool(_kEveningOn, v);

  /// Minutes after midnight. Default 08:00.
  static int get morningMinutes => _p?.getInt(_kMorningMin) ?? 8 * 60;
  static Future<void> setMorningMinutes(int v) async =>
      (await _prefs()).setInt(_kMorningMin, v);

  /// Minutes after midnight. Default 20:30.
  static int get eveningMinutes => _p?.getInt(_kEveningMin) ?? 20 * 60 + 30;
  static Future<void> setEveningMinutes(int v) async =>
      (await _prefs()).setInt(_kEveningMin, v);

  // ───────────── Small string store (cached texts, timestamps) ─────────────

  static String getString(String key) => _p?.getString(key) ?? '';
  static Future<void> putString(String key, String value) async =>
      (await _prefs()).setString(key, value);
}
