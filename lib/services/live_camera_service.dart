import 'dart:async';
import 'package:camera/camera.dart';

/// Live camera sampler.
///
/// Gemini doesn't accept video streams, so we send a single JPEG frame
/// every N seconds to the model for analysis. Not true video — but
/// useful for continuous awareness.
class LiveCameraService {
  CameraController? _controller;
  Timer? _timer;
  bool _running = false;

  CameraController? get controller => _controller;
  bool get isRunning => _running;

  Future<void> start({
    required Function(List<int> jpegBytes, String mime) onFrame,
    Duration interval = const Duration(seconds: 5),
  }) async {
    if (_running) return;
    final cams = await availableCameras();
    if (cams.isEmpty) throw Exception('No cameras available.');

    _controller = CameraController(cams.first, ResolutionPreset.medium);
    await _controller!.initialize();
    _running = true;

    _timer = Timer.periodic(interval, (_) async {
      try {
        final shot = await _controller!.takePicture();
        final bytes = await shot.readAsBytes();
        onFrame(bytes, 'image/jpeg');
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    await _controller?.dispose();
    _controller = null;
  }
}
