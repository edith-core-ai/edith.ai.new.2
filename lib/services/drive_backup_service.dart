import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Google Drive backup for chat history.
///
/// Requires a Google Cloud project with the Drive API enabled and an
/// OAuth client ID configured in the Android app. Until that's done,
/// signIn returns null and callers should handle it gracefully.
class DriveBackupService {
  static const _fileName = 'edith_backup.json';
  static const _scope = 'https://www.googleapis.com/auth/drive.file';

  final GoogleSignIn _signIn = GoogleSignIn(scopes: [_scope]);

  Future<GoogleSignInAccount?> signIn() async {
    final silent = await _signIn.signInSilently();
    return silent ?? await _signIn.signIn();
  }

  Future<void> signOut() => _signIn.signOut();

  Future<drive.DriveApi> _api() async {
    final acct = await signIn();
    if (acct == null) throw Exception('Google sign-in cancelled.');
    final auth = await acct.authentication;
    final client = _GoogleAuthClient(auth.accessToken!);
    return drive.DriveApi(client);
  }

  Future<String?> uploadBackup(String jsonPayload) async {
    final api = await _api();
    final existing =
        await api.files.list(q: "name='$_fileName'", spaces: 'drive');
    final bytes = utf8.encode(jsonPayload);
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (existing.files != null && existing.files!.isNotEmpty) {
      final id = existing.files!.first.id!;
      final updated = await api.files.update(drive.File(), id, uploadMedia: media);
      return updated.id;
    }
    final created = await api.files.create(
      drive.File()..name = _fileName,
      uploadMedia: media,
    );
    return created.id;
  }

  Future<String?> downloadBackup() async {
    final api = await _api();
    final list = await api.files.list(q: "name='$_fileName'", spaces: 'drive');
    if (list.files == null || list.files!.isEmpty) return null;
    final id = list.files!.first.id!;
    final media = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final chunks = <int>[];
    await for (final c in media.stream) chunks.addAll(c);
    return utf8.decode(chunks);
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();
  _GoogleAuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}
