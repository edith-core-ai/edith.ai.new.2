import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/edith_prefs.dart';
import '../services/gemini_endpoints.dart';
import '../services/live_voice_service.dart';
import '../services/reflection_service.dart';
import '../services/tool_router.dart';
import '../services/voice_out_service.dart';
import '../services/voice_input_service.dart';
import '../theme/edith_theme.dart';
import '../widgets/hand_control.dart';
import '../widgets/hologram_view.dart';
import 'live_camera_screen.dart';

class VoiceChatScreen extends StatefulWidget {
  /// True when opened by the wake word: start listening straight away.
  final bool autoStart;
  const VoiceChatScreen({super.key, this.autoStart = false});
  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  final _router = ToolRouter();
  final _tts = VoiceOutService();
  final _mic = VoiceInputService();
  final _uuid = const Uuid();
  final _hologram = HologramController();

  final List<Message> _history = [];
  String _transcript = '';
  String _reply = '';
  bool _listening = false;
  bool _thinking = false;
  bool _speaking = false;
  bool _hands = false;
  bool _live = false; // hands-free conversation, like a live call
  bool _gotFinal = false;

  // Real-time call (Gemini Live). Null when the older voice loop is used.
  LiveVoiceService? _call;
  bool _callConnecting = false;
  bool _muted = false;
  final String _sessionId = 'voice-${DateTime.now().millisecondsSinceEpoch}';

  // Blue while asleep, orange-red once she is awake and working.
  Color get _orbColor => (_live || _listening || _thinking || _speaking)
      ? const Color(0xFFFF5A1F)
      : const Color(0xFF2E9BFF);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Live chat: if the mic stops without a result, listen again.
    _mic.onEnded = () async {
      if (!mounted || !_live || _gotFinal || _thinking || _speaking) return;
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && _live && !_gotFinal && !_thinking && !_speaking) {
        await _startTurn();
      }
    };
    final ok = await _mic.init();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mic unavailable on this device.')),
      );
      return;
    }
    if (ok && mounted && widget.autoStart) await _toggleLive();
  }

  HologramMood get _mood {
    if (_speaking) return HologramMood.speaking;
    if (_thinking) return HologramMood.thinking;
    if (_listening) return HologramMood.listening;
    return HologramMood.idle;
  }

  String get _status {
    if (_callConnecting) return 'Connecting…';
    if (_speaking) return 'Speaking…';
    if (_thinking) return 'Thinking…';
    if (_listening) return 'Listening…';
    return _live ? 'Go ahead…' : 'Tap the mic to start';
  }

  /// Big mic button: starts a hands-free conversation, or ends it.
  Future<void> _toggleLive() async {
    if (_live) {
      await _endLive();
      return;
    }
    setState(() => _live = true);
    // Real-time call first; if it cannot start, the older loop takes over.
    if (EdithPrefs.liveVoice && await _startCall()) return;
    if (!mounted || !_live) return;
    await _startTurn();
  }

  Future<void> _endLive() async {
    final call = _call;
    _call = null;
    if (mounted) {
      setState(() {
        _live = false;
        _listening = false;
        _thinking = false;
        _speaking = false;
        _callConnecting = false;
        _muted = false;
      });
    }
    if (call != null) await call.stop();
    await _mic.stop();
    await _tts.stop();
    _learn();
  }

  /// Starts the Gemini Live call. Returns false if it could not start.
  Future<bool> _startCall() async {
    final call = LiveVoiceService(
      onState: (s) {
        if (!mounted) return;
        setState(() {
          _listening = s == LiveState.listening;
          _thinking = s == LiveState.thinking;
          _speaking = s == LiveState.speaking;
        });
        // The call ended by itself (connection lost, session over).
        if (s == LiveState.ended && _call != null) {
          _call = null;
          setState(() {
            _live = false;
            _muted = false;
          });
          _learn();
        }
      },
      onTranscript: (u, e) {
        if (!mounted) return;
        setState(() {
          _transcript = u;
          _reply = e;
        });
      },
      onTurn: (u, e) {
        final now = DateTime.now();
        if (u.isNotEmpty) {
          _history.add(Message(
            id: _uuid.v4(),
            role: 'user',
            content: u,
            timestamp: now,
            isVoiceTurn: true,
          ));
        }
        if (e.isNotEmpty) {
          _history.add(Message(
            id: _uuid.v4(),
            role: 'edith',
            content: e,
            timestamp: now,
            isVoiceTurn: true,
          ));
        }
      },
      onError: (m) {
        if (!mounted) return;
        setState(() => _reply = m);
      },
    );
    _call = call;
    setState(() => _callConnecting = true);
    final err = await call.start();
    if (!mounted) {
      await call.stop();
      return true;
    }
    setState(() => _callConnecting = false);
    if (err != null) {
      _call = null;
      final short = err.length > 160 ? err.substring(0, 160) : err;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Live call unavailable, using normal voice. $short')),
      );
      return false;
    }
    return true;
  }

  /// She reads this conversation and keeps what is worth keeping.
  void _learn() {
    if (_history.length < 4) return;
    ReflectionService.reflect(_sessionId, List<Message>.from(_history));
  }

  Future<void> _startTurn() async {
    if (_thinking) return;
    await _tts.stop();
    setState(() {
      _transcript = '';
      _reply = '';
      _speaking = false;
      _listening = true;
      _gotFinal = false;
    });
    await _mic.start((words, isFinal) async {
      if (!mounted) return;
      setState(() => _transcript = words);
      if (isFinal && words.trim().isNotEmpty && !_gotFinal) {
        _gotFinal = true;
        await _mic.stop();
        if (!mounted) return;
        setState(() => _listening = false);
        await _ask(words.trim());
      }
    });
    // If the mic could not start, do not stay stuck on "listening".
    if (mounted && !_mic.isAvailable) setState(() => _listening = false);
  }

  Future<void> _ask(String text) async {
    setState(() => _thinking = true);
    _history.add(Message(
      id: _uuid.v4(),
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
      isVoiceTurn: true,
    ));

    final buf = StringBuffer();
    try {
      await for (final chunk in _router.askWithTools(
        text,
        List<Message>.from(_history)..removeLast(),
        voiceMode: true,
      )) {
        buf.write(chunk);
        if (!mounted) return;
        setState(() => _reply = buf.toString());
      }
      final edith = Message(
        id: _uuid.v4(),
        role: 'edith',
        content: buf.toString(),
        timestamp: DateTime.now(),
        isVoiceTurn: true,
      );
      _history.add(edith);
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _speaking = true;
      });
      // Remove Markdown marks so the voice does not read "asterisk".
      await _tts.speak(edith.content.replaceAll(RegExp(r'[*#`_]'), ''));
      if (mounted && _tts.lastNote.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Used the phone voice. ${_tts.lastNote}')),
        );
      }
    } catch (e) {
      if (mounted) {
        // Stop the live loop so the error stays on screen.
        setState(() {
          _live = false;
          _reply = GeminiEndpoints.friendly(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _thinking = false;
          _speaking = false;
        });
        if (_live) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted && _live && !_thinking && !_listening) {
            await _startTurn();
          }
        }
      }
    }
  }

  @override
  void dispose() {
    final call = _call;
    _call = null;
    call?.stop();
    _learn();
    _mic.stop();
    _tts.dispose();
    _hologram.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = EdithTheme.electricBlue;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Deep-space backdrop.
          Positioned.fill(
            child: Image.asset(
              'assets/images/hologram_space.jpg',
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(0.6),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          // The live hologram. Drag to turn, pinch to zoom, double-tap to reset.
          Positioned.fill(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: _orbColor),
              duration: const Duration(milliseconds: 600),
              builder: (_, c, __) => HologramView(
                mood: _mood,
                controller: _hologram,
                color: c ?? _orbColor,
              ),
            ),
          ),
          if (_hands)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 60, 16, 0),
                  child: HandControl(controller: _hologram),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: EdithTheme.textPrimary),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                      const Spacer(),
                      if (_call != null && !_callConnecting)
                        IconButton(
                          icon: Icon(
                              _muted ? Icons.mic_off : Icons.mic_none_outlined,
                              color: _muted
                                  ? const Color(0xFFE5484D)
                                  : EdithTheme.textPrimary),
                          onPressed: () => setState(() {
                            _muted = !_muted;
                            _call?.setMuted(_muted);
                          }),
                        ),
                      GestureDetector(
                        onTap: _toggleLive,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _orbColor),
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_live ? Icons.lock_open : Icons.lock_outline,
                                  size: 14, color: _orbColor),
                              const SizedBox(width: 6),
                              Text(
                                _live ? 'SYSTEM ONLINE' : 'SYSTEM LOCKED',
                                style: TextStyle(
                                    color: _orbColor,
                                    fontSize: 11,
                                    letterSpacing: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _status,
                        style: const TextStyle(
                          color: EdithTheme.textSecondary,
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      if (_transcript.isNotEmpty)
                        Text(
                          _transcript,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: EdithTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      if (_reply.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          _reply,
                          textAlign: TextAlign.center,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: EdithTheme.textPrimary,
                            fontSize: 20,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _ControlBar(
                  accent: accent,
                  live: _live,
                  listening: _listening,
                  hands: _hands,
                  onCamera: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LiveCameraScreen()),
                  ),
                  onShare: () {
                    const ask = 'Look at my screen and tell me what you see.';
                    final call = _call;
                    if (call != null) {
                      call.sendText(ask);
                      return;
                    }
                    if (_thinking) return;
                    _ask(ask);
                  },
                  onHands: () => setState(() => _hands = !_hands),
                  onMic: _toggleLive,
                  onClose: () => Navigator.maybePop(context),
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Bottom row of round buttons: camera, hands, mic (big), close.
class _ControlBar extends StatelessWidget {
  final Color accent;
  final bool live;
  final bool listening;
  final bool hands;
  final VoidCallback onCamera;
  final VoidCallback onHands;
  final VoidCallback onShare;
  final VoidCallback onMic;
  final VoidCallback onClose;

  const _ControlBar({
    required this.accent,
    required this.live,
    required this.listening,
    required this.hands,
    required this.onCamera,
    required this.onHands,
    required this.onShare,
    required this.onMic,
    required this.onClose,
  });

  Widget _round(IconData icon, VoidCallback onTap,
      {bool on = false, Color? bg, Color? fg}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg ??
              (on
                  ? accent.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.10)),
        ),
        child: Icon(icon, color: fg ?? (on ? accent : Colors.white), size: 26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _round(Icons.videocam_outlined, onCamera),
          const SizedBox(width: 10),
          _round(Icons.screen_share_outlined, onShare),
          const SizedBox(width: 10),
          _round(Icons.back_hand_outlined, onHands, on: hands),
          const SizedBox(width: 10),
          _round(
            live ? Icons.mic : Icons.mic_off_outlined,
            onMic,
            bg: live ? accent : Colors.white.withValues(alpha: 0.10),
            fg: live ? Colors.black : Colors.white,
          ),
          const SizedBox(width: 10),
          _round(Icons.close, onClose,
              bg: const Color(0xFFE5484D), fg: Colors.white),
        ],
      ),
    );
  }
}
