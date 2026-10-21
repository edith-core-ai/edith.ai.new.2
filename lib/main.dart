import 'package:flutter/material.dart';
import 'theme/edith_theme.dart';
import 'screens/splash_screen.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.init();
  EdithTheme.setAccent(SettingsService.accentColor);
  runApp(const EdithApp());
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
