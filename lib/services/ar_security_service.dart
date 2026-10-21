import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class Detection {
  final Rect boundingBox;
  final String label;
  final double confidence;
  final bool isPerson;

  Detection({
    required this.boundingBox,
    required this.label,
    required this.confidence,
    this.isPerson = false,
  });
}

/// Camera HUD.
///
/// On-device object + face detection over the camera stream. Nothing
/// leaves the device. It only draws boxes and labels around what the
/// camera sees. It does not identify, track or rate anyone.
class ArSecurityService {
  CameraController? _controller;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  final ObjectDetector _objectDetector = ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  final _detections = StreamController<List<Detection>>.broadcast();
  Stream<List<Detection>> get detections => _detections.stream;

  bool _running = false;
  bool _busy = false;
  CameraController? get controller => _controller;

  /// Size of the upright (rotated) camera frame. The boxes in
  /// [detections] are in this coordinate space, so the screen needs it
  /// to scale them onto the preview.
  Size frameSize = Size.zero;

  Future<void> start() async {
    if (_running) return;
    final cams = await availableCameras();
    if (cams.isEmpty) throw Exception('No cameras available.');

    _controller = CameraController(
      cams.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _controller!.initialize();
    _running = true;
    _controller!.startImageStream(_processFrame);
  }

  Future<void> _processFrame(CameraImage image) async {
    // Drop frames while the previous one is still being analysed.
    if (_busy || !_running) return;
    _busy = true;
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final sideways = inputImage.metadata?.rotation ==
              InputImageRotation.rotation90deg ||
          inputImage.metadata?.rotation == InputImageRotation.rotation270deg;
      frameSize = sideways
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      final List<Detection> results = [];
      try {
        final faces = await _faceDetector.processImage(inputImage);
        for (final f in faces) {
          results.add(Detection(
            boundingBox: f.boundingBox,
            label: 'PERSON',
            confidence: 1.0,
            isPerson: true,
          ));
        }

        final objects = await _objectDetector.processImage(inputImage);
        for (final o in objects) {
          final label = o.labels.isNotEmpty ? o.labels.first.text : 'OBJECT';
          final conf = o.labels.isNotEmpty ? o.labels.first.confidence : 0.0;
          results.add(Detection(
            boundingBox: o.boundingBox,
            label: label.toUpperCase(),
            confidence: conf,
          ));
        }
      } catch (_) {
        // Skip a bad frame rather than killing the stream.
      }

      if (_running && !_detections.isClosed) _detections.add(results);
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final c = _controller;
    if (c == null) return null;

    final sensorOrientation = c.description.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    if (image.planes.isEmpty) return null;
    final bytes = image.planes.first.bytes;

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Future<void> stop() async {
    _running = false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    await _controller?.dispose();
    await _faceDetector.close();
    await _objectDetector.close();
    await _detections.close();
  }
}
