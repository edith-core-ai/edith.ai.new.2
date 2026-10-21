import 'attachment.dart';

class Message {
  final String id;
  final String role; // 'user' or 'edith'
  final String content;
  final DateTime timestamp;

  /// Set on user messages that came with a file attached.
  final Attachment? attachment;

  /// Set on EDITH messages whose reply is long enough to belong in a
  /// separate full-screen artifact view rather than the chat bubble.
  final bool isArtifact;

  /// A short human title for the artifact view.
  final String? artifactTitle;

  /// True when this message came from the voice chat screen.
  final bool isVoiceTurn;

  /// Local file path of an image the user sent (shown as a preview).
  final String? imagePath;

  Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.attachment,
    this.isArtifact = false,
    this.artifactTitle,
    this.isVoiceTurn = false,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'attachment': attachment?.toJson(),
        'isArtifact': isArtifact,
        'artifactTitle': artifactTitle,
        'isVoiceTurn': isVoiceTurn,
        'imagePath': imagePath,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'],
        role: json['role'],
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
        attachment: json['attachment'] != null
            ? Attachment.fromJson(json['attachment'] as Map<String, dynamic>)
            : null,
        isArtifact: json['isArtifact'] ?? false,
        artifactTitle: json['artifactTitle'],
        isVoiceTurn: json['isVoiceTurn'] ?? false,
        imagePath: json['imagePath'],
      );
}
