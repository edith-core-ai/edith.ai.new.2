import 'package:flutter/material.dart';
import '../theme/edith_theme.dart';

/// A small Markdown renderer for chat replies. No extra package.
///
/// Handles headings, bullet and numbered lists, fenced code blocks,
/// **bold**, *italic* and `inline code`. Everything is plain text in the
/// phone's normal font (code blocks use a fixed-width font so code lines
/// up). Wrapped in SelectionArea so the user can select and copy.
class MarkdownLite extends StatelessWidget {
  final String text;
  const MarkdownLite(this.text, {super.key});

  static const double _size = 15.5;
  static const double _height = 1.5;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _blocks(),
      ),
    );
  }

  List<Widget> _blocks() {
    final out = <Widget>[];
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Fenced code block.
      if (line.trimLeft().startsWith('```')) {
        final code = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          code.add(lines[i]);
          i++;
        }
        i++; // closing fence (or end of text while streaming)
        out.add(_codeBlock(code.join('\n')));
        continue;
      }

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Heading.
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final size = level == 1 ? 20.0 : (level == 2 ? 18.0 : 16.5);
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text.rich(
            TextSpan(
              children: _inline(heading.group(2)!),
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: EdithTheme.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ));
        i++;
        continue;
      }

      // Bullet list item.
      final bullet = RegExp(r'^(\s*)[-*•]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        final indent = bullet.group(1)!.length ~/ 2;
        out.add(_listItem('•', bullet.group(2)!, indent));
        i++;
        continue;
      }

      // Numbered list item.
      final numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (numbered != null) {
        final indent = numbered.group(1)!.length ~/ 2;
        out.add(_listItem('${numbered.group(2)}.', numbered.group(3)!, indent));
        i++;
        continue;
      }

      // Normal paragraph.
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text.rich(TextSpan(children: _inline(line), style: _base())),
      ));
      i++;
    }
    return out;
  }

  TextStyle _base() => const TextStyle(
        color: EdithTheme.textPrimary,
        fontSize: _size,
        height: _height,
      );

  Widget _listItem(String marker, String body, int indent) {
    return Padding(
      padding: EdgeInsets.only(left: 4.0 + indent * 16, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: marker.length > 2 ? 28 : 20,
            child: Text(marker, style: _base()),
          ),
          Expanded(
            child: Text.rich(TextSpan(children: _inline(body), style: _base())),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(String code) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EdithTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          style: const TextStyle(
            color: EdithTheme.textPrimary,
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  /// **bold**, *italic*, `code` inside one line.
  List<InlineSpan> _inline(String s) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`|\*[^*\s][^*]*\*)');
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (tok.startsWith('`')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            backgroundColor: EdithTheme.surfaceHigh,
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return spans;
  }
}
