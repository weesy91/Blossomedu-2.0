class User {
  final int id;
  final String username;
  final String name;
  final String? userType; // STUDENT, TEACHER, PARENT
  final bool isSuperuser;
  final String? position; // [NEW] TEACHER, VICE, PRINCIPAL, TA
  final int? branchId; // [NEW]

  User({
    required this.id,
    required this.username,
    required this.name,
    this.userType,
    this.isSuperuser = false,
    this.position,
    this.branchId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      name: json['name'] ?? '',
      userType: json['user_type'],
      isSuperuser: json['is_superuser'] ?? false,
      position: json['position'],
      branchId: json['branch_id'],
    );
  }
}
