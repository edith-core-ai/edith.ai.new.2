import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../brains/memory_brain.dart';
import '../models/chat_thread.dart';
import '../models/attachment.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';
import '../services/elevenlabs_service.dart';
import '../services/gemini_endpoints.dart';
import '../services/gemini_service.dart';
import '../services/voice_out_service.dart';
import '../services/settings_service.dart';
import '../services/tool_executor.dart';
import '../services/tool_router.dart';
import '../services/wake_word_service.dart';
import '../theme/edith_theme.dart';
import '../widgets/edith_drawer.dart';
import '../widgets/markdown_lite.dart';
import '../widgets/thinking_words.dart';
import 'ar_security_screen.dart';
import 'artifact_screen.dart';
import 'builder_screen.dart';
import 'discover_screen.dart';
import 'god_screen.dart';
import 'live_camera_screen.dart';
import 'missions_screen.dart';
import 'settings_screen.dart';
import 'voice_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _memory = MemoryBrain();
  final _gemini = GeminiService();
  final _toolRouter = ToolRouter();
  final _wakeWord = WakeWordService();
  final _attachments = AttachmentService();
  final _voice = ElevenLabsService();
  final _localVoice = VoiceOutService();
  final _player = AudioPlayer();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _uuid = const Uuid();
  final _imagePicker = ImagePicker();

  bool _waking = false;
  bool _autoSpeak = SettingsService.autoSpeak;
  String? _speakingMessageId;
  String? _currentThreadId;

  List<ChatThread> _threads = [];
  List<Message> _messages = [];
  bool _thinking = false;
  bool _attaching = false;

  // A picture or file waiting in the input bar for the next send.
  Attachment? _pendingFile;
  Uint8List? _pendingImage;
  String? _pendingImageMime;
  String? _pendingImagePath;
  String? _streamingMessageId;

  /// Ids of EDITH messages that are only error notices. They are shown
  /// on screen but never sent back to Gemini as conversation history.
  final Set<String> _errorIds = {};
  bool _think = false;
  bool _search = false;

  @override
  void initState() {
    super.initState();
    ToolExecutor.approve = _askApproval;
    _loadHistory();
    _controller.addListener(() => setState(() {}));
    if (SettingsService.wakeWordEnabled) _startWakeWord();
  }

  @override
  void dispose() {
    ToolExecutor.approve = null;
    _wakeWord.stop();
    _controller.dispose();
    _scrollController.dispose();
    _player.dispose();
    super.dispose();
  }

  // ───────────────────────── wake word ─────────────────────────

  Future<void> _startWakeWord() async {
    final started = await _wakeWord.start(() async {
      if (_waking || !mounted) return;
      _waking = true;
      await _wakeWord.stop();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => const VoiceChatScreen(autoStart: true)),
      );
      _waking = false;
      if (mounted && SettingsService.wakeWordEnabled) _startWakeWord();
    });
    if (!started && mounted) {
      _snack("Wake word couldn't start. ${_wakeWord.lastError}");
    }
  }

  /// Called after Settings closes, so the wake-word switch works at once.
  void _syncWakeWord() {
    if (SettingsService.wakeWordEnabled) {
      _startWakeWord();
    } else {
      _wakeWord.stop();
    }
  }

  // ───────────────────────── approvals ─────────────────────────

  /// Asked before EDITH sends an SMS or email or controls the phone.
  Future<bool> _askApproval(String title, String detail) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(detail)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ───────────────────────── voice out ─────────────────────────

  /// Removes Markdown marks so the voice does not read "asterisk".
  String _speakable(String text) => text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'[*#`_]'), '');

  Future<void> _speak(Message message) async {
    if (_speakingMessageId == message.id) {
      await _player.stop();
      await _localVoice.stop();
      setState(() => _speakingMessageId = null);
      return;
    }
    setState(() => _speakingMessageId = message.id);
    final text = _speakable(message.content);

    if (!SettingsService.useElevenLabs || !SettingsService.hasElevenLabsKey) {
      await _localVoice.speak(text);
      if (mounted) setState(() => _speakingMessageId = null);
      return;
    }

    try {
      final audioBytes = await _voice.synthesize(text);
      await _player.play(BytesSource(Uint8List.fromList(audioBytes)));
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _speakingMessageId = null);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _speakingMessageId = null);
        _snack("Couldn't generate speech, Boss. Check your ElevenLabs key.");
      }
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ───────────────────────── chats ─────────────────────────

  Future<void> _refreshThreads() async {
    final threads = await _memory.loadThreads();
    if (mounted) setState(() => _threads = threads);
  }

  Future<void> _loadHistory() async {
    var threadId = await _memory.getActiveThreadId();
    final threads = await _memory.loadThreads();
    if (threadId == null || !threads.any((t) => t.id == threadId)) {
      threadId = threads.first.id;
      await _memory.setActiveThreadId(threadId);
    }
    final history = await _memory.loadMessages(threadId);
    if (!mounted) return;
    setState(() {
      _threads = threads;
      _currentThreadId = threadId;
      _messages = history;
    });
    _scrollToBottom();
  }

  Future<void> _startNewChat() async {
    // An empty chat is already a fresh start. Do not pile up empty ones.
    if (_messages.isEmpty && _currentThreadId != null) return;
    final thread = await _memory.createThread();
    if (!mounted) return;
    setState(() {
      _currentThreadId = thread.id;
      _messages = [];
    });
    _refreshThreads();
  }

  Future<void> _selectThread(ChatThread thread) async {
    if (thread.id == _currentThreadId) return;
    await _memory.setActiveThreadId(thread.id);
    final history = await _memory.loadMessages(thread.id);
    if (!mounted) return;
    setState(() {
      _currentThreadId = thread.id;
      _messages = history;
    });
    _scrollToBottom();
  }

  Future<void> _renameThread(ChatThread thread) async {
    final controller = TextEditingController(text: thread.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _memory.renameThread(thread.id, newTitle);
      _refreshThreads();
    }
  }

  Future<void> _deleteThread(ChatThread thread) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text('"${thread.title}" will be gone for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final wasOpen = thread.id == _currentThreadId;
    await _memory.deleteThread(thread.id);
    if (wasOpen) {
      await _loadHistory();
    } else {
      await _refreshThreads();
    }
  }

  void _closeDrawer() => Navigator.of(context).pop();

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    setState(() => _autoSpeak = SettingsService.autoSpeak);
    _syncWakeWord();
  }

  // ───────────────────────── sending ─────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _shouldBeArtifact(String text) {
    if (text.length > 900) return true;
    final fenceCount = '```'.allMatches(text).length;
    if (fenceCount >= 2) return true;
    if (text.split('\n').length > 22) return true;
    return false;
  }

  String _artifactTitleFor(String text) {
    if (text.contains('```')) {
      final langMatch =
          RegExp(r'```(\w+)').firstMatch(text)?.group(1) ?? 'code';
      return '$langMatch code';
    }
    if (text.length > 900) return 'Document';
    return 'Artifact';
  }

  void _replaceMessage(String id, Message message) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx != -1) _messages[idx] = message;
  }

  /// One send path for text, files and pictures.
  /// [makeStream] gets the earlier messages and yields EDITH's reply text.
  Future<void> _runTurn(
    Message userMessage,
    Stream<String> Function(List<Message> history) makeStream,
  ) async {
    final threadId = _currentThreadId;
    if (threadId == null || _thinking) return;

    ToolExecutor.generatedImages.clear();
    ToolRouter.thinkHard = _think;
    ToolRouter.searchFirst = _search;
    final edithId = _uuid.v4();
    final started = DateTime.now();
    final history =
        _messages.where((m) => !_errorIds.contains(m.id)).toList();

    setState(() {
      _messages.add(userMessage);
      _messages.add(Message(
        id: edithId,
        role: 'edith',
        content: '',
        timestamp: started,
      ));
      _thinking = true;
      _streamingMessageId = edithId;
    });
    await _memory.saveMessage(threadId, userMessage);
    _refreshThreads();
    _scrollToBottom();

    final buffer = StringBuffer();
    Message finalMessage;
    var failed = false;
    try {
      await for (final chunk in makeStream(history)) {
        buffer.write(chunk);
        if (!mounted) break;
        setState(() => _replaceMessage(
              edithId,
              Message(
                id: edithId,
                role: 'edith',
                content: buffer.toString(),
                timestamp: started,
              ),
            ));
        _scrollToBottom();
      }
      var fullText = buffer.toString().trim();
      if (fullText.isEmpty) {
        fullText = "I didn't get an answer back, Boss. Try again.";
      }
      final asArtifact = _shouldBeArtifact(fullText);
      final madeImages = ToolExecutor.takeGeneratedImages();
      finalMessage = Message(
        id: edithId,
        role: 'edith',
        content: fullText,
        timestamp: started,
        isArtifact: asArtifact,
        artifactTitle: asArtifact ? _artifactTitleFor(fullText) : null,
        imagePath: madeImages.isNotEmpty ? madeImages.first : null,
      );
      if (_autoSpeak) _localVoice.speak(_speakable(fullText));
    } catch (e) {
      failed = true;
      final partial = buffer.toString().trim();
      final notice = GeminiEndpoints.friendly(e);
      finalMessage = Message(
        id: edithId,
        role: 'edith',
        content: partial.isEmpty ? notice : '$partial\n\n$notice',
        timestamp: started,
      );
    }

    if (mounted) {
      setState(() {
        if (failed) _errorIds.add(edithId);
        _replaceMessage(edithId, finalMessage);
        _streamingMessageId = null;
        _thinking = false;
      });
      _scrollToBottom();
    }
    // Errors are shown but not saved, so they never become history.
    if (!failed) await _memory.saveMessage(threadId, finalMessage);
    _refreshThreads();
  }

  /// Re-asks from a user message: everything after it is dropped, and the
  /// question (optionally with new text) goes out again. Used by Edit and
  /// Regenerate.
  Future<void> _resendFrom(int userIndex, {String? newText}) async {
    if (_thinking) return;
    final threadId = _currentThreadId;
    if (threadId == null) return;
    if (userIndex < 0 || userIndex >= _messages.length) return;
    final old = _messages[userIndex];
    if (old.role != 'user') return;

    setState(() => _messages.removeRange(userIndex, _messages.length));
    await _memory.replaceMessages(
      threadId,
      _messages.where((m) => !_errorIds.contains(m.id)).toList(),
    );

    final text = (newText ?? old.content).trim();
    final userMessage = Message(
      id: _uuid.v4(),
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
      imagePath: old.imagePath,
      attachment: old.attachment,
    );

    final imagePath = old.imagePath;
    if (imagePath != null && File(imagePath).existsSync()) {
      final bytes = await File(imagePath).readAsBytes();
      final mime = imagePath.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final ask = (text.isEmpty || text == '[Sent an image]')
          ? 'Describe this image.'
          : text;
      await _runTurn(userMessage, (history) async* {
        yield await _gemini.askWithImage(ask, bytes, mime);
      });
      return;
    }
    final file = old.attachment;
    final ask = (text.isEmpty || text.startsWith('[Sent:'))
        ? 'Read the attached file and respond.'
        : text;
    await _runTurn(
      userMessage,
      (history) => _toolRouter.askWithTools(ask, history, attachment: file),
    );
  }

  Future<void> _editMessage(int index) async {
    if (_thinking) return;
    final original = _messages[index].content;
    final start =
        (original == '[Sent an image]' || original.startsWith('[Sent:'))
            ? ''
            : original;
    final controller = TextEditingController(text: start);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final text = result.trim();
    if (text.isEmpty &&
        _messages[index].imagePath == null &&
        _messages[index].attachment == null) {
      return;
    }
    await _resendFrom(index, newText: text);
  }

  void _clearPending() {
    _pendingFile = null;
    _pendingImage = null;
    _pendingImageMime = null;
    _pendingImagePath = null;
  }

  /// One send path for plain text, text + picture, and text + file.
  /// A picture or file picked with "+" waits in the input bar, so the
  /// note is written first and everything goes out together.
  Future<void> _handleAsk([String? preset]) async {
    if (_thinking) return;
    final text = (preset ?? _controller.text).trim();
    final image = _pendingImage;
    final file = _pendingFile;
    if (text.isEmpty && image == null && file == null) return;

    if (image != null) {
      final mime = _pendingImageMime ?? 'image/jpeg';
      final path = _pendingImagePath;
      _controller.clear();
      setState(_clearPending);
      final userMessage = Message(
        id: _uuid.v4(),
        role: 'user',
        content: text.isEmpty ? '[Sent an image]' : text,
        timestamp: DateTime.now(),
        imagePath: path,
      );
      await _runTurn(userMessage, (history) async* {
        yield await _gemini.askWithImage(text, image, mime);
      });
      return;
    }

    if (file != null) {
      _controller.clear();
      setState(_clearPending);
      final userMessage = Message(
        id: _uuid.v4(),
        role: 'user',
        content: text.isEmpty ? '[Sent: ${file.name}]' : text,
        timestamp: DateTime.now(),
        attachment: file,
      );
      await _runTurn(
        userMessage,
        (history) => _toolRouter.askWithTools(
          text.isEmpty ? 'Read the attached file and respond.' : text,
          history,
          attachment: file,
        ),
      );
      return;
    }

    _controller.clear();
    final userMessage = Message(
      id: _uuid.v4(),
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );
    await _runTurn(
      userMessage,
      (history) => _toolRouter.askWithTools(text, history),
    );
  }

  /// Picks a file (any type, up to 100 MB) and holds it in the input bar.
  Future<void> _handleAttachFile() async {
    if (_thinking || _attaching) return;
    setState(() => _attaching = true);
    try {
      final attachment = await _attachments.pickAndRead();
      if (mounted) {
        setState(() {
          _clearPending();
          _pendingFile = attachment;
        });
      }
    } catch (e) {
      final text = e.toString().replaceFirst('Exception: ', '');
      if (mounted && !text.contains('No file selected')) {
        _snack("Couldn't read that file, Boss. $text");
      }
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  String _mimeOf(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  /// Picks a picture and holds it in the input bar until you send.
  Future<void> _handleImage(ImageSource source) async {
    if (_thinking) return;
    XFile? picked;
    try {
      picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) {
        _snack("Couldn't open the camera or gallery, Boss. Check the app's "
            'permissions in your phone settings.');
      }
      return;
    }
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final mimeType = _mimeOf(bytes);

    String? savedPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = mimeType == 'image/png'
          ? 'png'
          : (mimeType == 'image/webp' ? 'webp' : 'jpg');
      final file = File('${dir.path}/img_${_uuid.v4()}.$ext');
      await file.writeAsBytes(bytes);
      savedPath = file.path;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _clearPending();
      _pendingImage = bytes;
      _pendingImageMime = mimeType;
      _pendingImagePath = savedPath;
    });
  }

  void _showAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined,
                  color: EdithTheme.electricBlue),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _handleImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: EdithTheme.electricBlue),
              title: const Text('Choose a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _handleImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.attach_file,
                  color: EdithTheme.electricBlue),
              title: const Text('Attach a file'),
              subtitle: const Text('Any file up to 100 MB: PDF, Word, ZIP, code, text'),
              onTap: () {
                Navigator.pop(sheetContext);
                _handleAttachFile();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      onDrawerChanged: (open) {
        if (open) _refreshThreads();
      },
      drawer: EdithDrawer(
        threads: _threads,
        activeThreadId: _currentThreadId,
        profileName: 'Hilal',
        features: [
          DrawerFeature(
            icon: Icons.public,
            label: 'God Screen',
            onTap: () => _open(const GodScreen()),
          ),
          DrawerFeature(
            icon: Icons.newspaper,
            label: 'Discover',
            onTap: () => _open(const DiscoverScreen()),
          ),
          DrawerFeature(
            icon: Icons.construction,
            label: 'Builder',
            onTap: () => _open(const BuilderScreen()),
          ),
          DrawerFeature(
            icon: Icons.flag_outlined,
            label: 'Missions',
            onTap: () => _open(const MissionsScreen()),
          ),
          DrawerFeature(
            icon: Icons.mic_none_rounded,
            label: 'Voice',
            onTap: () => _open(const VoiceChatScreen()),
          ),
          DrawerFeature(
            icon: Icons.videocam_outlined,
            label: 'Camera',
            onTap: () => _open(const LiveCameraScreen()),
          ),
          DrawerFeature(
            icon: Icons.center_focus_strong_outlined,
            label: 'Camera HUD',
            onTap: () => _open(const ArSecurityScreen()),
          ),
        ],
        onNewChat: () {
          _closeDrawer();
          _startNewChat();
        },
        onSelect: (t) {
          _closeDrawer();
          _selectThread(t);
        },
        onRename: _renameThread,
        onDelete: _deleteThread,
        onSettings: () {
          _closeDrawer();
          _openSettings();
        },
      ),
      appBar: AppBar(
        title: const Text(
          'EDITH',
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_autoSpeak ? Icons.volume_up_outlined : Icons.volume_off_outlined),
            tooltip: _autoSpeak ? 'Mute replies' : 'Read replies aloud',
            onPressed: () {
              setState(() => _autoSpeak = !_autoSpeak);
              SettingsService.setAutoSpeak(_autoSpeak);
              if (!_autoSpeak) _localVoice.stop();
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_square),
            tooltip: 'New chat',
            onPressed: _startNewChat,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyState(onPick: (q) => _handleAsk(q))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        return _MessageBubble(
                          message: m,
                          isSpeaking: _speakingMessageId == m.id,
                          isStreaming: _streamingMessageId == m.id,
                          onSpeak: () => _speak(m),
                          onEdit: (m.role == 'user' && !_thinking)
                              ? () => _editMessage(i)
                              : null,
                          onRegenerate: (m.role != 'user' &&
                                  !_thinking &&
                                  i == _messages.length - 1 &&
                                  i > 0)
                              ? () => _resendFrom(i - 1)
                              : null,
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: m.content));
                            _snack('Copied.');
                          },
                          onOpenArtifact: m.isArtifact
                              ? () => _open(ArtifactScreen(
                                    title: m.artifactTitle ?? 'Artifact',
                                    content: m.content,
                                  ))
                              : null,
                        );
                      },
                    ),
            ),
            _Composer(
              controller: _controller,
              busy: _thinking,
              attaching: _attaching,
              pendingImage: _pendingImage,
              pendingFileName: _pendingFile?.name,
              onClearPending: () => setState(_clearPending),
              think: _think,
              search: _search,
              onThink: () => setState(() => _think = !_think),
              onSearch: () => setState(() => _search = !_search),
              onSend: _handleAsk,
              onPlus: _showAttachMenu,
              onVoice: () => _open(const VoiceChatScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── message bubble ─────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isSpeaking;
  final bool isStreaming;
  final VoidCallback onSpeak;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onOpenArtifact;

  const _MessageBubble({
    required this.message,
    required this.isSpeaking,
    required this.isStreaming,
    required this.onSpeak,
    required this.onCopy,
    this.onEdit,
    this.onRegenerate,
    this.onOpenArtifact,
  });

  Widget _withEdit(Widget bubble) {
    if (onEdit == null) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        _SmallIcon(icon: Icons.edit_outlined, tooltip: 'Edit', onTap: onEdit!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final imagePath = message.imagePath;
    final hasImage = imagePath != null && File(imagePath).existsSync();
    final showText = !(hasImage && message.content == '[Sent an image]');

    final picture = hasImage
        ? Padding(
            padding: EdgeInsets.only(bottom: showText ? 8 : 0),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => _ImageViewer(path: imagePath)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(imagePath),
                    width: 220, fit: BoxFit.cover),
              ),
            ),
          )
        : null;

    final fileRow = message.attachment == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.attach_file,
                    size: 14, color: EdithTheme.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    message.attachment!.name,
                    style: const TextStyle(
                        color: EdithTheme.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );

    if (isUser) {
      return _withEdit(Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: const BoxDecoration(
            color: EdithTheme.surfaceHigh,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (picture != null) picture,
              if (fileRow != null) fileRow,
              if (showText)
                SelectableText(
                  message.content,
                  style: const TextStyle(
                    color: EdithTheme.textPrimary,
                    fontSize: 15.5,
                    height: 1.45,
                  ),
                ),
            ],
          ),
        ),
      ));
    }

    // EDITH: plain text, no box.
    final waiting = message.content.isEmpty && isStreaming;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (picture != null && !waiting) picture,
            if (waiting)
              const ThinkingWords()
            else
              MarkdownLite(message.content),
            if (message.isArtifact && onOpenArtifact != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenArtifact,
                  icon: const Icon(Icons.open_in_full, size: 16),
                  label: Text(
                    'Open ${message.artifactTitle ?? "artifact"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  ),
                ),
              ),
            if (!isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SmallIcon(
                      icon: Icons.copy_outlined,
                      tooltip: 'Copy',
                      onTap: onCopy,
                    ),
                    _SmallIcon(
                      icon: isSpeaking
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      tooltip: isSpeaking ? 'Stop' : 'Read aloud',
                      onTap: onSpeak,
                    ),
                    if (onRegenerate != null)
                      _SmallIcon(
                        icon: Icons.refresh,
                        tooltip: 'Try again',
                        onTap: onRegenerate!,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _SmallIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      tooltip: tooltip,
      color: EdithTheme.textSecondary,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }
}

class _ImageViewer extends StatelessWidget {
  final String path;
  const _ImageViewer({required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: InteractiveViewer(child: Image.file(File(path))),
      ),
    );
  }
}

// ───────────────────────── empty state ─────────────────────────

class _EmptyState extends StatelessWidget {
  final void Function(String) onPick;
  const _EmptyState({required this.onPick});

  static const _ideas = [
    "Give me today's top news",
    'Help me plan my day',
    'Explain something simply',
    'Write a message for me',
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Very faint hologram art behind the greeting.
        Positioned.fill(
          child: Image.asset(
            'assets/images/hologram_bg.jpg',
            fit: BoxFit.cover,
            opacity: const AlwaysStoppedAnimation(0.10),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'How can I help, Boss?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final idea in _ideas)
                      ActionChip(
                        label: Text(idea),
                        backgroundColor: EdithTheme.surface,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        onPressed: () => onPick(idea),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── input bar ─────────────────────────

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final bool attaching;
  final Uint8List? pendingImage;
  final String? pendingFileName;
  final VoidCallback onClearPending;
  final VoidCallback onSend;
  final VoidCallback onPlus;
  final VoidCallback onVoice;

  final bool think;
  final bool search;
  final VoidCallback onThink;
  final VoidCallback onSearch;

  const _Composer({
    required this.controller,
    required this.busy,
    required this.attaching,
    required this.pendingImage,
    required this.pendingFileName,
    required this.think,
    required this.search,
    required this.onThink,
    required this.onSearch,
    required this.onClearPending,
    required this.onSend,
    required this.onPlus,
    required this.onVoice,
  });

  Widget _chip(IconData icon, String label, bool on, VoidCallback onTap) {
    final c = on ? EdithTheme.electricBlue : EdithTheme.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on
              ? EdithTheme.electricBlue.withValues(alpha: 0.15)
              : EdithTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: on ? EdithTheme.electricBlue : EdithTheme.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: c, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// The small card above the text box showing what will be sent.
  Widget _pendingCard() {
    final image = pendingImage;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EdithTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(image, width: 56, height: 56, fit: BoxFit.cover),
            )
          else
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: EdithTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.insert_drive_file_outlined,
                  color: EdithTheme.electricBlue),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              image != null ? 'Picture ready. Add a note, then send.' : pendingFileName ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EdithTheme.textPrimary,
                fontSize: 13.5,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: EdithTheme.textSecondary),
            tooltip: 'Remove',
            onPressed: onClearPending,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingImage != null || pendingFileName != null;
    final canSend = controller.text.trim().isNotEmpty || hasPending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPending) _pendingCard(),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _chip(Icons.psychology_outlined, 'Think', think, onThink),
                const SizedBox(width: 8),
                _chip(Icons.public, 'Search', search, onSearch),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: EdithTheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: attaching
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: EdithTheme.electricBlue,
                          ),
                        )
                      : const Icon(Icons.add, color: EdithTheme.textPrimary),
                  tooltip: 'Attach',
                  onPressed: (attaching || busy) ? null : onPlus,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: EdithTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: hasPending
                          ? 'Type a message about this (optional)'
                          : 'Message EDITH',
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (canSend)
                  Container(
                    margin: const EdgeInsets.only(right: 4, bottom: 4),
                    decoration: BoxDecoration(
                      color: busy
                          ? EdithTheme.electricBlue.withValues(alpha: 0.4)
                          : EdithTheme.electricBlue,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded,
                          color: Colors.black),
                      tooltip: 'Send',
                      onPressed: busy ? null : onSend,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.mic_none_rounded,
                        color: EdithTheme.textPrimary),
                    tooltip: 'Voice chat',
                    onPressed: onVoice,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
