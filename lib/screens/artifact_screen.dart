import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/edith_theme.dart';

/// Full-screen artifact view for long replies (code, plans, documents).
class ArtifactScreen extends StatelessWidget {
  final String title;
  final String content;

  const ArtifactScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title.toUpperCase(),
          style: const TextStyle(
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: EdithTheme.surface,
                  content: Text(
                    'Copied to clipboard.',
                    style: TextStyle(color: EdithTheme.electricBlue),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          content,
          style: const TextStyle(
            color: EdithTheme.textPrimary,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}
