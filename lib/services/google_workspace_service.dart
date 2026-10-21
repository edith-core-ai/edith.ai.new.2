import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;

/// Google Workspace integration — Calendar + Gmail.
///
/// Uses the same Google account the user picks for Drive backup.
/// Scopes: calendar (read/write) + gmail.readonly + gmail.send.
class GoogleWorkspaceService {
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events',
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
  ];

  final GoogleSignIn _signIn = GoogleSignIn(scopes: _scopes);

  Future<GoogleSignInAccount?> signIn() async {
    final silent = await _signIn.signInSilently();
    return silent ?? await _signIn.signIn();
  }

  Future<void> signOut() => _signIn.signOut();

  Future<_AuthClient> _client() async {
    final acct = await signIn();
    if (acct == null) throw Exception('Google sign-in cancelled.');
    final auth = await acct.authentication;
    return _AuthClient(auth.accessToken!);
  }

  // ─────────── Calendar ───────────

  Future<String> listUpcomingEvents({int max = 10}) async {
    final calApi = cal.CalendarApi(await _client());
    final now = DateTime.now().toUtc().toIso8601String();
    final events = await calApi.events.list(
      'primary',
      timeMin: DateTime.parse(now),
      maxResults: max,
      singleEvents: true,
      orderBy: 'startTime',
    );
    final items = events.items ?? [];
    if (items.isEmpty) return 'No upcoming events.';
    final buf = StringBuffer('Upcoming events:\n');
    for (final e in items) {
      final start = e.start?.dateTime ?? e.start?.date;
      buf.writeln('• ${e.summary ?? "(no title)"} — $start');
    }
    return buf.toString();
  }

  Future<String> createEvent({
    required String title,
    required DateTime start,
    DateTime? end,
  }) async {
    final calApi = cal.CalendarApi(await _client());
    final e = cal.Event()
      ..summary = title
      ..start = cal.EventDateTime(dateTime: start.toUtc())
      ..end = cal.EventDateTime(
        dateTime: (end ?? start.add(const Duration(hours: 1))).toUtc(),
      );
    final created = await calApi.events.insert(e, 'primary');
    return 'Created "${created.summary}" on '
        '${created.start?.dateTime ?? created.start?.date}.';
  }

  // ─────────── Gmail ───────────

  Future<String> listRecentEmails({int max = 5}) async {
    final g = gmail.GmailApi(await _client());
    final list = await g.users.messages.list(
      'me',
      maxResults: max,
      q: 'is:unread',
    );
    final ids = list.messages ?? [];
    if (ids.isEmpty) return 'No unread emails.';

    final buf = StringBuffer('Recent unread:\n');
    for (final m in ids) {
      final full = await g.users.messages.get('me', m.id!, format: 'metadata');
      final headers = full.payload?.headers ?? [];
      String? subj;
      String? from;
      for (final h in headers) {
        if (h.name == 'Subject') subj = h.value;
        if (h.name == 'From') from = h.value;
      }
      buf.writeln('• ${subj ?? "(no subject)"} — ${from ?? "unknown"}');
    }
    return buf.toString();
  }

  Future<String> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    final g = gmail.GmailApi(await _client());
    // Strip line breaks so text from the model cannot add hidden headers
    // (for example a secret Bcc). Encode non-English subjects properly.
    final safeTo = to.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    final oneLine = subject.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    final safeSubject = oneLine.runes.every((r) => r < 128)
        ? oneLine
        : '=?UTF-8?B?${base64.encode(utf8.encode(oneLine))}?=';
    final raw = 'To: $safeTo\r\n'
        'Subject: $safeSubject\r\n'
        'Content-Type: text/plain; charset="UTF-8"\r\n\r\n'
        '$body';
    final encoded = base64Url.encode(utf8.encode(raw));
    final msg = gmail.Message()..raw = encoded;
    await g.users.messages.send(msg, 'me');
    return 'Email sent to $safeTo.';
  }
}

class _AuthClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();
  _AuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}