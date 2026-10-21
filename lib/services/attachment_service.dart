import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/attachment.dart';

/// Reads a picked file and turns it into plain text so EDITH can reason
/// over it. Works for text, code, PDF, Word, PowerPoint, Excel and ZIP
/// files up to 100 MB. Pictures go through the vision path instead.
class AttachmentService {
  static const int maxBytes = 100 * 1024 * 1024; // 100 MB
  static const int _maxPromptChars = 300000;

  Future<Attachment> pickAndRead() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      throw Exception('No file selected.');
    }

    final picked = result.files.first;
    final path = picked.path;
    if (path == null) throw Exception('Could not open the file.');

    final file = File(path);
    final size = await file.length();
    if (size > maxBytes) {
      throw Exception(
          'File too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). '
          'The limit is 100 MB.');
    }
    final bytes = await file.readAsBytes();

    final ext = (picked.extension ?? '').toLowerCase();
    var text = await _extract(bytes, ext, picked.name, size);
    if (text.length > _maxPromptChars) {
      text = '${text.substring(0, _maxPromptChars)}\n\n'
          '[Cut here: the file is longer than I can read in one go.]';
    }

    return Attachment(
      name: picked.name,
      mimeType: _mimeFor(ext),
      sizeBytes: size,
      textContent: text,
    );
  }

  static const _textExts = {
    'txt', 'md', 'csv', 'tsv', 'json', 'yaml', 'yml', 'xml', 'html', 'htm',
    'css', 'js', 'ts', 'tsx', 'jsx', 'dart', 'py', 'java', 'kt', 'c', 'cpp',
    'h', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'sql', 'swift', 'gradle',
    'properties', 'ini', 'toml', 'log', 'cfg', 'conf', 'env', 'gitignore',
    'lock', 'rtf',
  };

  Future<String> _extract(
      List<int> bytes, String ext, String name, int size) async {
    if (ext == 'pdf') return _extractPdf(bytes);
    if (ext == 'zip' || ext == 'docx' || ext == 'pptx' || ext == 'xlsx') {
      return compute(_extractArchiveText, <Object>[bytes, ext]);
    }
    if (_textExts.contains(ext) || ext.isEmpty) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    final mb = (size / 1024 / 1024).toStringAsFixed(1);
    return '[Binary file "$name", $mb MB, type .$ext. I can see its name and '
        'size but cannot read what is inside this kind of file.]';
  }

  String _extractPdf(List<int> bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    final buffer = StringBuffer();
    final extractor = PdfTextExtractor(doc);
    for (var i = 0; i < doc.pages.count; i++) {
      buffer.writeln(extractor.extractText(startPageIndex: i, endPageIndex: i));
      buffer.writeln();
    }
    doc.dispose();
    return buffer.toString();
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'md':
        return 'text/markdown';
      case 'zip':
        return 'application/zip';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'text/plain';
    }
  }
}

// ───────────── runs on a background isolate (see compute above) ─────────────

const _zipTextExts = {
  'txt', 'md', 'csv', 'tsv', 'json', 'yaml', 'yml', 'xml', 'html', 'htm',
  'css', 'js', 'ts', 'tsx', 'jsx', 'dart', 'py', 'java', 'kt', 'c', 'cpp',
  'h', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'sql', 'swift', 'gradle',
  'properties', 'ini', 'toml', 'log', 'cfg', 'conf',
};

String _extractArchiveText(List<Object> args) {
  final bytes = args[0] as List<int>;
  final ext = args[1] as String;
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return '[Could not open this file. It may be damaged or protected with '
        'a password.]';
  }

  if (ext == 'docx') return _officeText(archive, ['word/document.xml']);
  if (ext == 'pptx') {
    final slides = archive.files
        .where((f) =>
            f.isFile &&
            f.name.startsWith('ppt/slides/slide') &&
            f.name.endsWith('.xml'))
        .map((f) => f.name)
        .toList()
      ..sort();
    return _officeText(archive, slides);
  }
  if (ext == 'xlsx') {
    return _officeText(archive, ['xl/sharedStrings.xml']);
  }

  // Plain ZIP: list everything, then read the text-like files inside.
  final out = StringBuffer();
  final files = archive.files.where((f) => f.isFile).toList();
  out.writeln('ZIP file with ${files.length} files:');
  for (final f in files.take(300)) {
    out.writeln('- ${f.name} (${f.size} bytes)');
  }
  if (files.length > 300) out.writeln('- ...and ${files.length - 300} more');
  out.writeln();

  var total = 0;
  var read = 0;
  for (final f in files) {
    if (read >= 80 || total > 250000) break;
    final dot = f.name.lastIndexOf('.');
    final fext = dot == -1 ? '' : f.name.substring(dot + 1).toLowerCase();
    if (!_zipTextExts.contains(fext) || f.size > 200000) continue;
    try {
      final text = utf8.decode(f.content as List<int>, allowMalformed: true);
      out.writeln('===== ${f.name} =====');
      out.writeln(text);
      out.writeln();
      total += text.length;
      read++;
    } catch (_) {}
  }
  if (read == 0) out.writeln('(No readable text files inside.)');
  return out.toString();
}

String _officeText(Archive archive, List<String> names) {
  final out = StringBuffer();
  for (final name in names) {
    final matches = archive.files.where((f) => f.isFile && f.name == name);
    if (matches.isEmpty) continue;
    final xml = utf8.decode(matches.first.content as List<int>,
        allowMalformed: true);
    out.writeln(_xmlToText(xml));
    out.writeln();
  }
  final text = out.toString().trim();
  return text.isEmpty ? '(No readable text found in this document.)' : text;
}

String _xmlToText(String xml) {
  return xml
      .replaceAll(RegExp(r'</w:p>|</a:p>|</si>|<w:br\s*/>|<w:tab\s*/>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
}
