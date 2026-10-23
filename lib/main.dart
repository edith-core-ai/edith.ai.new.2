import 'dart:async';
import 'package:flutter/material.dart';
import 'theme/edith_theme.dart';
import 'screens/splash_screen.dart';
import 'services/settings_service.dart';

/// Any startup error is shown on screen instead of leaving a frozen logo.
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) => FlutterError.presentError(d);
    ErrorWidget.builder = (d) => Material(
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Text('EDITH error:\n${d.exceptionAsString()}',
                  style: const TextStyle(color: Colors.orangeAccent)),
            ),
          ),
        );
    runApp(const _Boot());
  }, (e, s) {
    debugPrint('EDITH uncaught: $e\n$s');
  });
}

/// Draws a first frame at once, then loads settings. If loading fails or
/// takes too long, the reason is written on screen.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await SettingsService.init().timeout(const Duration(seconds: 15));
      EdithTheme.setAccent(SettingsService.accentColor);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const EdithApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error == null
                ? const CircularProgressIndicator()
                : Text('Startup problem:\n$_error',
                    style: const TextStyle(color: Colors.orangeAccent)),
          ),
        ),
      ),
    );
  }
}

class EdithApp extends StatelessWidget {
  const EdithApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole theme the moment the accent colour changes.
    return ValueListenableBuilder<Color>(
      valueListenable: EdithTheme.accent,
      builder: (context, _, __) => MaterialApp(
        title: 'E.D.I.T.H.',
        debugShowCheckedModeBanner: false,
        theme: EdithTheme.theme,
        home: const SplashScreen(),
      ),
    );
  }
}
