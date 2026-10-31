class Member {
  final String uid;
  final String name;
  final String email;
  final String role;
  final DateTime joinedAt;

  Member({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
  });

  factory Member.fromMap(
    Map<String, dynamic> map,
  ) {
    return Member(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'Member',
      joinedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'joinedAt':
          joinedAt.toIso8601String(),
    };
  }
}