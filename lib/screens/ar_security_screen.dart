import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/ar_security_service.dart';
import '../theme/edith_theme.dart';

class ArSecurityScreen extends StatefulWidget {
  const ArSecurityScreen({super.key});
  @override
  State<ArSecurityScreen> createState() => _ArSecurityScreenState();
}

class _ArSecurityScreenState extends State<ArSecurityScreen> {
  final _svc = ArSecurityService();
  final List<String> _log = [];
  List<Detection> _frame = [];
  Size _frameSize = Size.zero;
  Set<String> _lastLabels = {};
  bool _ready = false;
  String? _error;
  DateTime _sessionStart = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _boot();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _boot() async {
    try {
      await _svc.start();
      _sessionStart = DateTime.now();
      _svc.detections.listen((d) {
        if (!mounted) return;
        // Log only what newly came into view, not every frame.
        final labels = d.map((x) => x.label).toSet();
        final fresh = labels.difference(_lastLabels);
        _lastLabels = labels;
        setState(() {
          _frame = d;
          _frameSize = _svc.frameSize;
          for (final label in fresh) {
            _log.insert(0, '[${_ts()}] Spotted — $label');
          }
          while (_log.length > 40) {
            _log.removeLast();
          }
        });
      });
      setState(() => _ready = true);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _ts() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _clock?.cancel();
    _svc.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _svc.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error: $_error',
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _ready && c != null && c.value.isInitialized
                    ? Stack(
                        children: [
                          Positioned.fill(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: c.value.previewSize!.height,
                                height: c.value.previewSize!.width,
                                child: CameraPreview(c),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _HudPainter(
                                detections: _frame,
                                frameSize: _frameSize,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: CircularProgressIndicator(
                          color: EdithTheme.electricBlue,
                        ),
                      ),
          ),
          _buildTopHud(),
          _buildBottomHud(),
        ],
      ),
    );
  }

  Widget _buildTopHud() {
    final elapsed = DateTime.now().difference(_sessionStart).inSeconds;
    final people = _frame.where((d) => d.isPerson).length;
    final objects = _frame.length - people;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.black.withValues(alpha: 0.55),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: EdithTheme.electricBlue,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CAMERA HUD',
                      style: TextStyle(
                        color: EdithTheme.electricBlue,
                        fontSize: 12,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'T+${elapsed}s   PEOPLE:$people  OBJECTS:$objects',
                      style: const TextStyle(
                        color: EdithTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: EdithTheme.electricBlue,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'LIVE',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHud() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          height: 140,
          color: Colors.black.withValues(alpha: 0.7),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EVENT LOG',
                style: TextStyle(
                  color: EdithTheme.electricBlue,
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _log.isEmpty
                    ? const Text(
                        '— no events —',
                        style: TextStyle(
                          color: EdithTheme.textSecondary,
                          fontSize: 12,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            _log[i],
                            style: TextStyle(
                              color: EdithTheme.electricBlue,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  final List<Detection> detections;
  final Size frameSize;
  _HudPainter({required this.detections, required this.frameSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (frameSize.isEmpty) return;
    // The preview fills the screen with BoxFit.cover, so map the camera
    // frame onto the canvas the same way.
    final scale = math.max(
        size.width / frameSize.width, size.height / frameSize.height);
    final dx = (size.width - frameSize.width * scale) / 2;
    final dy = (size.height - frameSize.height * scale) / 2;

    for (final d in detections) {
      final color = d.isPerson ? EdithTheme.electricBlue : Colors.white70;

      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final raw = d.boundingBox;
      final box = Rect.fromLTRB(
        raw.left * scale + dx,
        raw.top * scale + dy,
        raw.right * scale + dx,
        raw.bottom * scale + dy,
      );
      const len = 18.0;

      canvas.drawLine(
          Offset(box.left, box.top), Offset(box.left + len, box.top), paint);
      canvas.drawLine(
          Offset(box.left, box.top), Offset(box.left, box.top + len), paint);
      canvas.drawLine(
          Offset(box.right, box.top), Offset(box.right - len, box.top), paint);
      canvas.drawLine(
          Offset(box.right, box.top), Offset(box.right, box.top + len), paint);
      canvas.drawLine(Offset(box.left, box.bottom),
          Offset(box.left + len, box.bottom), paint);
      canvas.drawLine(Offset(box.left, box.bottom),
          Offset(box.left, box.bottom - len), paint);
      canvas.drawLine(Offset(box.right, box.bottom),
          Offset(box.right - len, box.bottom), paint);
      canvas.drawLine(Offset(box.right, box.bottom),
          Offset(box.right, box.bottom - len), paint);

      final label = '${d.label}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelBg = Paint()..color = Colors.black.withValues(alpha: 0.7);
      final labelRect = Rect.fromLTWH(
        box.left,
        box.top - tp.height - 4,
        tp.width + 8,
        tp.height + 4,
      );
      canvas.drawRect(labelRect, labelBg);
      tp.paint(canvas, Offset(box.left + 4, box.top - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _HudPainter oldDelegate) =>
      oldDelegate.detections != detections ||
      oldDelegate.frameSize != frameSize;
}
