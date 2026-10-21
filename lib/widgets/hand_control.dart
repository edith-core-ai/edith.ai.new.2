import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../theme/edith_theme.dart';
import 'hand_tracker_page.dart';
import 'hologram_view.dart';

/// A hidden camera view that watches your hands and steers the
/// hologram: pinch with one hand and move to spin it, pinch with both
/// hands and spread or close them to zoom.
///
/// The tracking runs in a WebView (see hand_tracker_page.dart). The
/// camera is only on while this widget is on screen.
class HandControl extends StatefulWidget {
  final HologramController controller;
  const HandControl({super.key, required this.controller});

  @override
  State<HandControl> createState() => _HandControlState();
}

class _HandControlState extends State<HandControl> {
  WebViewController? _web;
  String _status = 'Starting camera…';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final cam = await Permission.camera.request();
    if (!mounted) return;
    if (!cam.isGranted) {
      setState(() {
        _failed = true;
        _status = 'Camera permission is off';
      });
      return;
    }

    final web = WebViewController(
      onPermissionRequest: (request) {
        // Android already granted the camera above; let the page use it.
        request.grant();
      },
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('EdithHands', onMessageReceived: _onMessage)
      ..loadHtmlString(handTrackerHtml, baseUrl: 'https://edith.app/');

    // Android blocks camera video from starting by itself unless this is off.
    final platform = web.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
    }

    if (mounted) setState(() => _web = web);
  }

  void _onMessage(JavaScriptMessage message) {
    if (!mounted) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (data['t']) {
      case 'rotate':
        final dx = (data['dx'] as num).toDouble();
        final dy = (data['dy'] as num).toDouble();
        // Dragging down tips the front of the hologram down.
        widget.controller.rotateBy(dx, -dy);
        break;
      case 'zoom':
        final f = (data['f'] as num).toDouble();
        // Hands apart (f below 1) means closer, so the hologram grows.
        if (f > 0) widget.controller.zoomBy(1.0 / f);
        break;
      case 'loading':
        setState(() => _status = 'Loading hand tracking…');
        break;
      case 'ready':
        setState(() => _status = 'Show your hand');
        break;
      case 'status':
        final hands = (data['hands'] as num).toInt();
        final mode = data['mode'] as String? ?? 'idle';
        setState(() {
          if (mode == 'spin') {
            _status = 'Spinning';
          } else if (mode == 'zoom') {
            _status = 'Zooming';
          } else if (hands == 0) {
            _status = 'Show your hand';
          } else {
            _status = 'Pinch to grab';
          }
        });
        break;
      case 'error':
        setState(() {
          _failed = true;
          final why = (data['msg'] ?? '').toString();
          _status = "Hands didn't start. "
              '${why.length > 90 ? why.substring(0, 90) : why}';
        });
        break;
    }
  }

  @override
  void dispose() {
    // Blank page so the camera is released.
    _web?.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // The camera view is kept running but invisible: no face on screen.
        Opacity(
          opacity: 0.02,
          child: SizedBox(
            width: 112,
            height: 150,
            child: web == null
                ? const SizedBox.shrink()
                : WebViewWidget(controller: web),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 150,
          child: Text(
            _status,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: _failed ? Colors.redAccent : EdithTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
