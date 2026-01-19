class Announcement {
  final int id;
  final String title;
  final String content;
  final String? image;
  final String authorName;
  final String createdAt;
  final bool isActive;

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    this.image,
    required this.authorName,
    required this.createdAt,
    required this.isActive,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      image: json['image'],
      authorName: json['author_name'] ?? 'Unknown',
      createdAt: json['created_at'],
      isActive: json['is_active'] ?? true,
    );
  }
}
