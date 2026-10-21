import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/chat_thread.dart';

/// Memory Brain — v0.5 (real multi-thread chat history)
///
/// Previously this saved one continuous log under a single key. Now each
/// conversation is its own thread: a `ChatThread` record in the threads
/// index, plus its own message list under `edith_messages_<threadId>`.
///
/// On first run after upgrading, any old single-log history found under
/// the legacy `edith_message_history` key is migrated into a thread
/// called "Imported Chat" so nobody loses history.
class MemoryBrain {
  static const _threadsKey = 'edith_threads';
  static const _activeThreadKey = 'edith_active_thread_id';
  static const _legacyHistoryKey = 'edith_message_history';
  static const _uuid = Uuid();

  /// Titles that mean "no real title yet". The first real user message
  /// replaces them.
  static const _placeholderTitles = {'New Chat', 'Image chat'};

  String _messagesKey(String threadId) => 'edith_messages_$threadId';

  /// Short, clean chat title made from a user message.
  static String titleFrom(String content) {
    final text = content.trim();
    if (text == '[Sent an image]') return 'Image chat';
    final file = RegExp(r'^\[Sent: (.+)\]$').firstMatch(text);
    if (file != null) {
      final name = file.group(1)!.trim();
      return name.length > 32 ? '${name.substring(0, 32)}…' : name;
    }
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'New Chat';
    final short = words.take(6).join(' ');
    return short.length > 36 ? '${short.substring(0, 36)}…' : short;
  }

  /// One-line preview for the thread list. Never shows raw "[Sent ...]".
  static String _previewFrom(String content) {
    final text = content.trim();
    if (text == '[Sent an image]') return 'Image';
    if (RegExp(r'^\[Sent: (.+)\]$').hasMatch(text)) return 'File';
    final one = text.replaceAll(RegExp(r'\s+'), ' ');
    return one.length > 60 ? '${one.substring(0, 60)}…' : one;
  }

  /// Deletes the picture files of a thread so deleted chats do not keep
  /// filling the phone's storage.
  Future<void> _deleteSavedImages(String threadId) async {
    try {
      final messages = await loadMessages(threadId);
      for (final m in messages) {
        final path = m.imagePath;
        if (path == null) continue;
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {
      // Best effort only.
    }
  }

  /// Returns all threads, most-recently-updated first. Migrates legacy
  /// single-log history and/or creates a first thread if none exist yet.
  Future<List<ChatThread>> loadThreads() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getStringList(_threadsKey) ?? [];

    if (raw.isEmpty) {
      final legacy = prefs.getStringList(_legacyHistoryKey) ?? [];
      if (legacy.isNotEmpty) {
        // Migrate old single-thread history into a real thread.
        final thread = ChatThread(
          id: _uuid.v4(),
          title: 'Imported Chat',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          preview: 'Migrated from earlier version',
        );
        await prefs.setStringList(_messagesKey(thread.id), legacy);
        await prefs.remove(_legacyHistoryKey);
        raw = [jsonEncode(thread.toJson())];
        await prefs.setStringList(_threadsKey, raw);
      } else {
        // Brand new install: start with one empty thread so the app
        // always has something to show/select.
        final thread = await createThread(title: 'New Chat');
        return [thread];
      }
    }

    final threads = raw
        .map((s) => ChatThread.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return threads;
  }

  Future<void> _saveThreads(List<ChatThread> threads) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _threadsKey,
      threads.map((t) => jsonEncode(t.toJson())).toList(),
    );
  }

  Future<ChatThread> createThread({String title = 'New Chat'}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_threadsKey) ?? [];
    final threads = raw
        .map((s) => ChatThread.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();

    final thread = ChatThread(
      id: _uuid.v4(),
      title: title,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    threads.add(thread);
    await _saveThreads(threads);
    await setActiveThreadId(thread.id);
    return thread;
  }

  Future<void> renameThread(String threadId, String newTitle) async {
    final threads = await loadThreads();
    final thread = threads.firstWhere((t) => t.id == threadId);
    thread.title = newTitle.trim().isEmpty ? thread.title : newTitle.trim();
    await _saveThreads(threads);
  }

  Future<void> deleteThread(String threadId) async {
    final prefs = await SharedPreferences.getInstance();
    await _deleteSavedImages(threadId);
    final threads = await loadThreads();
    threads.removeWhere((t) => t.id == threadId);
    await _saveThreads(threads);
    await prefs.remove(_messagesKey(threadId));
    if (await getActiveThreadId() == threadId) {
      if (threads.isNotEmpty) {
        await setActiveThreadId(threads.first.id);
      } else {
        await prefs.remove(_activeThreadKey);
      }
    }
  }

  Future<String?> getActiveThreadId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeThreadKey);
  }

  Future<void> setActiveThreadId(String threadId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeThreadKey, threadId);
  }

  Future<List<Message>> loadMessages(String threadId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_messagesKey(threadId)) ?? [];
    return raw
        .map((s) => Message.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMessage(String threadId, Message message) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_messagesKey(threadId)) ?? [];
    raw.add(jsonEncode(message.toJson()));
    await prefs.setStringList(_messagesKey(threadId), raw);

    // Keep the thread's title (auto, from the first user message),
    // preview and updatedAt fresh so the threads list stays useful.
    final threads = await loadThreads();
    final index = threads.indexWhere((t) => t.id == threadId);
    if (index != -1) {
      final thread = threads[index];
      thread.updatedAt = DateTime.now();
      thread.preview = _previewFrom(message.content);
      if (_placeholderTitles.contains(thread.title) &&
          message.role == 'user') {
        thread.title = titleFrom(message.content);
      }
      await _saveThreads(threads);
    }
  }

  /// Replaces the whole saved message list of a thread (used when a
  /// message is edited or a reply is regenerated).
  Future<void> replaceMessages(String threadId, List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _messagesKey(threadId),
      messages.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  Future<void> clearThreadMessages(String threadId) async {
    await _deleteSavedImages(threadId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messagesKey(threadId));
  }
}
