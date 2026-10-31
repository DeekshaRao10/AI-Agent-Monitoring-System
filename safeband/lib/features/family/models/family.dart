class Family {
  final String id;
  final String familyName;
  final String inviteCode;
  final String createdBy;

  Family({
    required this.id,
    required this.familyName,
    required this.inviteCode,
    required this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'familyName': familyName,
      'inviteCode': inviteCode,
      'createdBy': createdBy,
    };
  }
}