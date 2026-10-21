/// A text file the user attached to a message (txt, pdf, code, ...).
class Attachment {
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String textContent;

  /// Saved copies are capped so one big PDF cannot fill phone storage.
  static const int maxSavedChars = 20000;

  Attachment({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.textContent,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'textContent': textContent.length > maxSavedChars
            ? textContent.substring(0, maxSavedChars)
            : textContent,
      };

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        name: json['name'] as String? ?? 'file',
        mimeType: json['mimeType'] as String? ?? 'text/plain',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        textContent: json['textContent'] as String? ?? '',
      );
}
