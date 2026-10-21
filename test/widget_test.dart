import 'package:edith_app/brains/memory_brain.dart';
import 'package:edith_app/services/gemini_endpoints.dart';
import 'package:edith_app/theme/edith_theme.dart';
import 'package:edith_app/widgets/markdown_lite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat titles are short and clean', () {
    expect(MemoryBrain.titleFrom('[Sent an image]'), 'Image chat');
    expect(MemoryBrain.titleFrom('[Sent: notes.pdf]'), 'notes.pdf');
    expect(MemoryBrain.titleFrom('What is the weather like in Lagos today'),
        'What is the weather like in');
  });

  test('errors become one friendly sentence', () {
    expect(
      GeminiEndpoints.friendly(Exception('Gemini request failed (429): x')),
      contains('free Gemini limit'),
    );
    expect(
      GeminiEndpoints.friendly(Exception(GeminiEndpoints.noKeyMarker)),
      contains('Settings'),
    );
  });

  testWidgets('markdown renders', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: EdithTheme.theme,
      home: const Scaffold(body: MarkdownLite('Hello **world**\n\n- one\n- two')),
    ));
    expect(find.byType(MarkdownLite), findsOneWidget);
  });
}
