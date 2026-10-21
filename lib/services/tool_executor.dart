import 'dart:convert';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'google_workspace_service.dart';
import 'native_tools_service.dart';
import 'phone_agent_service.dart';
import 'phone_control_service.dart';
import 'settings_service.dart';
import 'web_service.dart';
import 'image_gen_service.dart';

class ToolExecutor {
  static String get openWeatherApiKey => SettingsService.openWeatherKey;
  static String get newsApiKey => SettingsService.newsApiKey;

  /// Set once by the home screen. Called before any action that sends
  /// something out or controls the phone. Returns true only if the user
  /// taps Allow. This stops text inside notifications, emails or web
  /// pages from tricking EDITH into acting on its own.
  static Future<bool> Function(String title, String detail)? approve;

  /// Pictures made during the current reply. The chat screen shows them.
  static final List<String> generatedImages = [];

  static List<String> takeGeneratedImages() {
    final out = List<String>.from(generatedImages);
    generatedImages.clear();
    return out;
  }

  Future<String> _generateImage(Map<String, dynamic> a) async {
    final path = await _images.generate(a['prompt'] as String);
    if (path == null) {
      return 'I could not make the picture: ${ImageGenService.lastError}';
    }
    generatedImages.add(path);
    return 'The picture was created and is now shown in the chat.';
  }

  static const String _notApproved =
      'The user did not approve this action, so it was not done.';

  Future<bool> _approved(String title, String detail) async {
    final ask = approve;
    if (ask == null) return false;
    return ask(title, detail);
  }

  static String? _screenshotImage;
  static String? takeScreenshotImage() {
    final v = _screenshotImage;
    _screenshotImage = null;
    return v;
  }

  /// Waits a few seconds (so Hilal can switch to the app he means), then
  /// captures the screen and hands it to the model as a picture.
  Future<String> _lookAtScreen(Map<String, dynamic> args) async {
    final secs = ((args['seconds'] as num?)?.toInt() ?? 4).clamp(0, 15);
    final pc = PhoneControlService();
    final st = await pc.status();
    if (st != 'running') {
      return 'Phone control is not running, so I cannot see the screen. '
          'Turn on the EDITH Accessibility service first.';
    }
    if (secs > 0) await Future.delayed(Duration(seconds: secs));
    final b64 = await pc.screenshot();
    if (b64 == null) {
      return 'Could not capture the screen (needs Android 11 or newer and '
          'the Accessibility service running).';
    }
    _screenshotImage = b64;
    return 'Screenshot captured. It is attached right after this result: '
        'describe or use what you see.';
  }

  final GoogleWorkspaceService _google = GoogleWorkspaceService();
  final PhoneAgentService _agent = PhoneAgentService();
  final NativeToolsService _native = NativeToolsService();
  final WebService _web = WebService();
  final ImageGenService _images = ImageGenService();

  Future<String> execute(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        // Tier 1
        case 'send_sms': return await _sendSms(args);
        case 'send_sms_direct': return await _sendSmsDirect(args);
        case 'make_call': return await _makeCall(args);
        case 'open_url': return await _openUrl(args);
        case 'share_text': return await _shareText(args);
        case 'set_alarm': return await _setAlarm(args);
        case 'set_reminder': return await _setReminder(args);
        case 'get_clipboard': return await _getClipboard();
        case 'set_clipboard': return await _setClipboard(args);
        case 'get_weather': return await _getWeather(args);
        case 'get_news': return await _getNews(args);
        case 'play_music': return await _playMusic(args);
        case 'open_app': return await _openApp(args);
        case 'remember':
          await SettingsService.addMemory(args['fact'] as String);
          return 'Saved to memory.';
        case 'forget':
          final n = await SettingsService.forgetMatching(args['text'] as String);
          return n == 0 ? 'Nothing matched.' : 'Forgot $n memory item(s).';
        case 'generate_image': return await _generateImage(args);
        case 'look_at_screen': return await _lookAtScreen(args);
        case 'web_search': return await _web.search(args['query'] as String);
        case 'read_webpage': return await _web.readPage(args['url'] as String);

        // Tier 2
        case 'list_calendar_events': return await _listCalendar(args);
        case 'create_calendar_event': return await _createEvent(args);
        case 'list_emails': return await _listEmails(args);
        case 'send_email': return await _sendEmail(args);

        // Tier 3
        case 'read_contacts': return await _readContacts(args);
        case 'lookup_contact': return await _lookupContact(args);
        case 'read_notifications': return await _readNotifications(args);

        // Tier 4
        case 'whatsapp_message': return await _whatsappMessage(args);
        case 'whatsapp_call': return await _whatsappCall(args);
        case 'whatsapp_share': return await _whatsappShare(args);
        case 'automate_task': return await _automateTask(args);

        default:
          return 'Unknown tool: $name';
      }
    } catch (e) {
      return 'Tool "$name" failed: $e';
    }
  }

  // ─────────── Tier 1 ───────────

  Future<String> _sendSms(Map<String, dynamic> a) async {
    final uri = Uri.parse(
        'sms:${a['to']}?body=${Uri.encodeComponent(a['body'] as String)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return 'Opened SMS app to ${a['to']}.';
    }
    return 'Could not open SMS app.';
  }

  Future<String> _sendSmsDirect(Map<String, dynamic> a) async {
    final raw = (a['to'] as String).trim();
    if (!await _approved('Send this SMS?', 'To: $raw\n\n${a['body']}')) {
      return _notApproved;
    }
    // If the "to" looks like a name (not digits), resolve via contacts.
    String phone = raw;
    if (!RegExp(r'^\+?\d').hasMatch(raw)) {
      final resolved = await _native.lookupContactNumber(raw);
      if (resolved == null) {
        return 'No contact found matching "$raw".';
      }
      phone = resolved;
    }
    await _native.sendSmsDirect(phone, a['body'] as String);
    return 'SMS sent to $phone.';
  }

  Future<String> _makeCall(Map<String, dynamic> a) async {
    final uri = Uri.parse('tel:${a['number']}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return 'Opened dialer for ${a['number']}.';
    }
    return 'Could not open dialer.';
  }

  Future<String> _openUrl(Map<String, dynamic> a) async {
    final uri = Uri.parse(a['url'] as String);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return 'Opened ${a['url']}.';
    }
    return 'Could not open URL.';
  }

  Future<String> _shareText(Map<String, dynamic> a) async {
    await Share.share(a['text'] as String);
    return 'Share sheet opened.';
  }

  Future<String> _setAlarm(Map<String, dynamic> a) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': a['hour'],
        'android.intent.extra.alarm.MINUTES': a['minute'],
        'android.intent.extra.alarm.MESSAGE': a['label'] ?? 'EDITH alarm',
        'android.intent.extra.alarm.SKIP_UI': false,
      },
    );
    await intent.launch();
    return 'Alarm set for ${a['hour']}:${a['minute']}.';
  }

  Future<String> _setReminder(Map<String, dynamic> a) async {
    final start = DateTime.tryParse(a['start_iso'] as String) ?? DateTime.now();
    final end = start.add(const Duration(hours: 1));
    final intent = AndroidIntent(
      action: 'android.intent.action.INSERT',
      data: 'content://com.android.calendar/events',
      arguments: {
        'title': a['title'],
        'beginTime': start.millisecondsSinceEpoch,
        'endTime': end.millisecondsSinceEpoch,
      },
    );
    await intent.launch();
    return 'Opened calendar to create "${a['title']}".';
  }

  Future<String> _getClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text ?? '(clipboard empty)';
  }

  Future<String> _setClipboard(Map<String, dynamic> a) async {
    await Clipboard.setData(ClipboardData(text: a['text'] as String));
    return 'Copied to clipboard.';
  }

  Future<String> _getWeather(Map<String, dynamic> a) async {
    if (openWeatherApiKey.isEmpty || openWeatherApiKey.startsWith('PASTE_')) {
      return 'No weather key yet. Add an OpenWeather key in Settings → Tools.';
    }
    final city = a['city'] as String;
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/weather'
      '?q=${Uri.encodeComponent(city)}'
      '&appid=$openWeatherApiKey&units=metric',
    );
    final res = await http.get(url);
    if (res.statusCode != 200) {
      return 'Weather lookup failed (${res.statusCode}).';
    }
    final j = jsonDecode(res.body);
    return '$city: ${j['weather']?[0]?['description']}, '
        '${j['main']?['temp']}°C, ${j['main']?['humidity']}% humidity.';
  }

  Future<String> _getNews(Map<String, dynamic> a) async {
    if (newsApiKey.isEmpty || newsApiKey.startsWith('PASTE_')) {
      return 'No news key yet. Add a NewsAPI key in Settings → Tools.';
    }
    final topic = a['topic'] as String;
    final url = Uri.parse(
      'https://newsapi.org/v2/everything'
      '?q=${Uri.encodeComponent(topic)}'
      '&pageSize=5&sortBy=publishedAt&apiKey=$newsApiKey',
    );
    final res = await http.get(url);
    if (res.statusCode != 200) return 'News lookup failed (${res.statusCode}).';
    final j = jsonDecode(res.body);
    final arts = (j['articles'] as List?) ?? [];
    if (arts.isEmpty) return 'No recent articles on "$topic".';
    final buf = StringBuffer('Top $topic headlines:\n');
    for (final art in arts.take(5)) {
      buf.writeln('• ${art['title']} — ${art['source']?['name']}');
    }
    return buf.toString();
  }

  Future<String> _playMusic(Map<String, dynamic> a) async {
    final q = Uri.encodeComponent(a['query'] as String);
    final uri = Uri.parse('https://music.youtube.com/search?q=$q');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return 'Opened music search for "${a['query']}".';
    }
    return 'Could not open music app.';
  }

  Future<String> _openApp(Map<String, dynamic> a) async {
    final pkg = a['package'] as String?;
    if (pkg != null && pkg.contains('.')) {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: pkg,
        category: 'android.intent.category.LAUNCHER',
      ).launch();
      return 'Launched $pkg.';
    }
    final name = (a['name'] ?? pkg ?? '').toString();
    final opened = await PhoneControlService().launchApp(name);
    return opened == null
        ? 'I could not find an app called "$name" on this phone.'
        : 'Opened $opened.';
  }

  // ─────────── Tier 2 ───────────

  Future<String> _listCalendar(Map<String, dynamic> a) async {
    final max = (a['max'] as num?)?.toInt() ?? 10;
    return await _google.listUpcomingEvents(max: max);
  }

  Future<String> _createEvent(Map<String, dynamic> a) async {
    final start = DateTime.tryParse(a['start_iso'] as String);
    if (start == null) return 'Invalid start_iso.';
    final end = a['end_iso'] != null
        ? DateTime.tryParse(a['end_iso'] as String)
        : null;
    return await _google.createEvent(
      title: a['title'] as String,
      start: start,
      end: end,
    );
  }

  Future<String> _listEmails(Map<String, dynamic> a) async {
    final max = (a['max'] as num?)?.toInt() ?? 5;
    return await _google.listRecentEmails(max: max);
  }

  Future<String> _sendEmail(Map<String, dynamic> a) async {
    if (!await _approved('Send this email?',
        'To: ${a['to']}\nSubject: ${a['subject']}\n\n${a['body']}')) {
      return _notApproved;
    }
    return await _google.sendEmail(
      to: a['to'] as String,
      subject: a['subject'] as String,
      body: a['body'] as String,
    );
  }

  // ─────────── Tier 3 ───────────

  Future<String> _readContacts(Map<String, dynamic> a) async {
    final filter = (a['filter'] as String?)?.toLowerCase();
    final contacts = await _native.readContacts();
    final filtered = filter == null || filter.isEmpty
        ? contacts
        : contacts
            .where((c) =>
                (c['name'] ?? '').toLowerCase().contains(filter))
            .toList();
    if (filtered.isEmpty) return 'No contacts found.';
    final buf = StringBuffer('Contacts (${filtered.length}):\n');
    for (final c in filtered.take(30)) {
      buf.writeln('• ${c['name']} — ${c['number']}');
    }
    return buf.toString();
  }

  Future<String> _lookupContact(Map<String, dynamic> a) async {
    final name = a['name'] as String;
    final number = await _native.lookupContactNumber(name);
    return number == null
        ? 'No contact found matching "$name".'
        : '$name: $number';
  }

  Future<String> _readNotifications(Map<String, dynamic> a) async {
    final limit = (a['limit'] as num?)?.toInt() ?? 10;
    final notes = await _native.readNotifications(limit: limit);
    if (notes.isEmpty) return 'No recent notifications.';
    final buf = StringBuffer('Recent notifications (${notes.length}):\n');
    for (final n in notes) {
      buf.writeln('• [${n['package']}] ${n['title']} — ${n['text']}');
    }
    return buf.toString();
  }

  // ─────────── Tier 4 ───────────

  Future<String> _whatsappMessage(Map<String, dynamic> a) async {
    final raw = (a['phone'] as String).trim();
    final message = a['message'] as String;
    final business = a['business'] == true;

    // A name instead of a number: look it up in contacts.
    var phone = raw;
    if (!RegExp(r'^\+?\d').hasMatch(raw)) {
      final resolved = await _native.lookupContactNumber(raw);
      if (resolved == null) return 'No contact found matching "$raw".';
      phone = resolved;
    }
    phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) return 'I need a phone number for that contact.';

    if (!await _approved(
        'Send this WhatsApp message?', 'To: $raw ($phone)\n\n$message')) {
      return _notApproved;
    }

    final url =
        'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
    final packages = business
        ? ['com.whatsapp.w4b', 'com.whatsapp']
        : ['com.whatsapp', 'com.whatsapp.w4b'];
    var opened = false;
    for (final pkg in packages) {
      try {
        await AndroidIntent(
          action: 'action_view',
          data: url,
          package: pkg,
        ).launch();
        opened = true;
        break;
      } catch (_) {}
    }
    if (!opened) return 'WhatsApp is not installed or could not open.';

    // Press Send for the user, if phone control is on.
    final ctl = PhoneControlService();
    if (!await ctl.isEnabled()) {
      return 'Opened the chat with $raw and typed the message. Phone control '
          'is off, so tap Send yourself.';
    }
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (await ctl.tapByText('Send')) {
        return 'Message sent to $raw on WhatsApp.';
      }
    }
    return 'Opened the chat with $raw and typed the message, but I could not '
        'find the Send button. Tap Send yourself.';
  }

  Future<String> _whatsappCall(Map<String, dynamic> a) async {
    final phone = a['phone'] as String;
    final uri = Uri.parse('https://wa.me/$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return 'Opened WhatsApp chat with $phone (tap call).';
    }
    return 'Could not open WhatsApp.';
  }

  Future<String> _whatsappShare(Map<String, dynamic> a) async {
    final msg = Uri.encodeComponent(a['message'] as String);
    final uri = Uri.parse('https://wa.me/?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return 'Opened WhatsApp contact picker.';
    }
    return 'Could not open WhatsApp.';
  }

  Future<String> _automateTask(Map<String, dynamic> a) async {
    final instruction = a['instruction'] as String;
    if (!await _approved('Let EDITH control your phone?', instruction)) {
      return _notApproved;
    }
    return await _agent.runTask(instruction);
  }
}