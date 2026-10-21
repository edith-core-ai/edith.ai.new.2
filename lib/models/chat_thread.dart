/// A single saved conversation thread — v0.5 (real multi-thread history).
class ChatThread {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String preview;

  ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.preview = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'preview': preview,
      };

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
        id: json['id'],
        title: json['title'],
        createdAt: DateTime.parse(json['createdAt']),
        updatedAt: DateTime.parse(json['updatedAt']),
        preview: json['preview'] ?? '',
      );
}
