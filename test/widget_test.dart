import 'package:edith_app/brains/memory_brain.dart';
import 'package:edith_app/brains/memory_core.dart';
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

  test('private data is never saved as a memory', () {
    expect(MemoryCore.isSafeToStore('Hilal likes strong coffee'), isTrue);
    expect(MemoryCore.isSafeToStore('My password is hunter2'), isFalse);
    expect(MemoryCore.isSafeToStore('Card 4111 1111 1111 1111'), isFalse);
  });

  testWidgets('markdown renders', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: EdithTheme.theme,
      home: const Scaffold(body: MarkdownLite('Hello **world**\n\n- one\n- two')),
    ));
    expect(find.byType(MarkdownLite), findsOneWidget);
  });
}
