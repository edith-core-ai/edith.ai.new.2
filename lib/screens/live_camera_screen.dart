import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/gemini_endpoints.dart';
import '../services/gemini_service.dart';
import '../services/live_camera_service.dart';
import '../theme/edith_theme.dart';

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});
  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  final _svc = LiveCameraService();
  final _gem = GeminiService();
  final List<String> _insights = [];
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _addInsight(String text) {
    if (!mounted) return;
    // Do not repeat the same error line every few seconds.
    if (_insights.isNotEmpty && _insights.first == text) return;
    setState(() {
      _insights.insert(0, text);
      if (_insights.length > 6) _insights.removeLast();
    });
  }

  Future<void> _start() async {
    try {
      await _svc.start(onFrame: (bytes, mime) async {
        try {
          final reply = await _gem.askWithImage(
            'Briefly describe what is happening in this frame.',
            Uint8List.fromList(bytes),
            mime,
          );
          _addInsight(reply);
        } catch (e) {
          _addInsight(GeminiEndpoints.friendly(e));
        }
      });
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't open the camera, Boss. Allow Camera "
            "for this app in your phone's settings.");
      }
    }
  }

  @override
  void dispose() {
    _svc.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _svc.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: Column(
        children: [
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: EdithTheme.textSecondary),
                      ),
                    ),
                  )
                : _ready && c != null && c.value.isInitialized
                ? CameraPreview(c)
                : Center(
                    child: CircularProgressIndicator(
                      color: EdithTheme.electricBlue,
                    ),
                  ),
          ),
          Container(
            height: 180,
            color: EdithTheme.surface,
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              itemCount: _insights.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _insights[i],
                  style: TextStyle(
                    color: EdithTheme.electricBlue,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
