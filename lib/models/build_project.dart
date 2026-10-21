class BuildProject {
  final String id;
  final String title;
  final String plan;
  final DateTime createdAt;

  BuildProject({
    required this.id,
    required this.title,
    required this.plan,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'plan': plan,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BuildProject.fromJson(Map<String, dynamic> json) => BuildProject(
        id: json['id'],
        title: json['title'],
        plan: json['plan'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}
