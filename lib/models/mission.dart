class Mission {
  final String id;
  final String title;
  final String? notes;
  bool completed;
  final DateTime createdAt;

  Mission({
    required this.id,
    required this.title,
    this.notes,
    this.completed = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
        id: json['id'],
        title: json['title'],
        notes: json['notes'],
        completed: json['completed'] ?? false,
        createdAt: DateTime.parse(json['createdAt']),
      );
}
